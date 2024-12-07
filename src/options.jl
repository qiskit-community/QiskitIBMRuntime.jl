# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

module Options

using SumTypes: SumTypes, @sum_type, @cases
using ArgCheck: @argcheck # , @check
using ..Parameters2: @with_kw
using ..Utils: Utils, @pretty_show
import ..Utils: to_rest_api
import ..Types: Opt
import ..ConvertCase:
    LowerCase, SnakeCase, KebabCase, SameCase, conversion_case, convert_case, snake_to_camel

using ConstructionBase: ConstructionBase
using StructEquality: @struct_hash_equal

export AbstractParams,
    Auto,
    DDSequenceType,
    DynamicalDecouplingOptions,
    EstimatorExecutionOptions,
    EstimatorOptions,
    ExtraSlackType,
    LayerNoiseOptions,
    MeasType,
    MeasureNoiseLearningOptions,
    NoiseLearnerOptions,
    None,
    PECOptions,
    ResilienceOptions,
    SamplerExecutionOptions,
    SamplerOptions,
    SchedulingType,
    SimulatorOptions,
    TwirlingOptions,
    TwirlingStrategy,
    ZNEOptions

"""
    struct Auto end

Value for some options signifying "determined automatically".
"""
struct Auto end

"""
    struct None end

Value for some options signifying "no limit".
"""
struct None end

abstract type AbstractParams end

abstract type AbstractOptionEnum end

"""
    to_rest_api(obj::AbstractParams)

Convert `obj` to JSON-able `Dict`, removing `nothing` and empty `Dict`s
"""
function to_rest_api(obj::AbstractParams)
    named_tup = ConstructionBase.getfields(obj)
    # Base.filter turns the sequence of pairs into a Dict. :(
    # Base.filter is faster than here than Iterators.filter. Not uncommon in Julia :(.

    # Filter out the value `nothing` and empty Dicts
    filt = x -> begin
        val = x[2]
        isnothing(val) && return false
        isa(val, Dict) && isempty(val) && return false
        return true
    end
    filt_res = Iterators.filter(filt, pairs(named_tup))

    mapf = x -> x[1] => to_rest_api(x[2])
    # Call `to_rest_api` recursively, and then filter out `nothing` again.
    dict = Dict{Symbol,Any}(Iterators.filter(filt, map(mapf, filt_res)))
    return dict
    #    return post_process_options(obj, dict)
end

# function post_process_options(obj, dict)
#     return dict
# end

function to_rest_api(obj::AbstractOptionEnum)
    tag = string(SumTypes.get_tag(obj))
    return convert_case(tag, conversion_case(obj))
end

function Base.convert(T::Type{<:AbstractOptionEnum}, opt::AbstractString)
    return adjoint(T)[Symbol(snake_to_camel(opt))]
end

#function Base.convert(T::Type{<:Vector{<:AbstractOptionEnum}}, opt::AbstractString)
function Base.convert(
    ::Type{<:Vector{T}},
    opt::AbstractString,
) where {T<:AbstractOptionEnum}
    return [adjoint(T)[Symbol(snake_to_camel(opt))]]
end

# For complicated conditions, @argcheck does not print the value passed.
# In this case, @got_val(varname) will print it.
# @got_val(varname) will print it. "Got varname => value."
#
#     @got_val
#
# `got_val(varname)` expands to a `LazyString` equivalent of `"Got varname => \$varname"`.
macro got_val(x)
    sym = QuoteNode(x)
    return esc(:(LazyString("Got ", $sym, " => ", $x, ".")))
end

"""
    @params

Decorates a `struct` definition to add features for Primitive options

* All fields may be set positionally or by keyword.
* All types are wrapped in `Opt{T}`. For example, `x::Int` becomes `x::Opt{Int}`.
* Currently, `Opt{T}=Union{T, Nothing}`, and the default value for every field is `nothing`,
  signifying `unset`.
* `@argcheck` and similar macros are supported for validation. The substitution
  `predicate(x)` ⟶ `isnothing(x) || predicate(x)` is made in validation macro arguments.
   For example `isnothing(x) || x > 0`. This substitution refers to the most recent field.
   In particular, validation of a field must occur before the next field is defined.
* Special types `Auto` and `None` are detected in order to modify the predicate as is done
  for `Nothing` in the previous item.
* Supported validation/assertion macros are `@assert`, `@smart_assert`, `@check`, `@argcheck`.
  Because this is a macro, we don't need to depend on or import the corresponding package; for
  example `SmartAsserts.jl`. At present, in applications of `@params` we import and use `ArgCheck.jl`.
* Shortcut `Symbol`s are: GT0, GE0, GE1. These write the appropriate `@argcheck`. If the type of
  field is a `Vector`, then `all` is called with the predicate.
* `QiskitRuntime.Utils.@pretty_show` is written for the struct name.

!!! details
    Development notes

    The validation macros are supported simply by looking for the macro call name in a list of allowed
    macro names. The macros are all moved (by `@with_kw`) to one place to validate the arguments. Presumably
    other macros (or even code) could be supported simply by allowing any macro call. With the caveat
    that the assertion argument would not be rewritten.

    `@params` makes use of `Parameters.jl`, or more precisely, our vendored, patched version in
    `parameters2.jl`. The original is old and crufty. It's probably bette to write a new custom, minimal
    macro.
"""
macro params(code)
    return esc(_write_params(code))
end

function _write_params(code)
    isa(code, Expr) && code.head === :struct ||
        throw(ArgumentError("Expecting `struct` definition"))
    struct_name = code.args[2]
    code.args[2] = :($struct_name <: AbstractParams)
    struct_body = code.args[3]
    fields = struct_body.args # fields and LineNumberNode, and String, and anything else.
    var = nothing
    type_ = nothing
    got_auto = false
    got_none = false
    for (i, item) in enumerate(fields)
        item isa LineNumberNode && continue
        item isa String && continue
        if item isa Symbol
            # Note that these will be rewritten below in the branch for :macrocall
            if item === :GT0
                cf = :(>(0))
            elseif item === :GE0
                cf = :(>=(0))
            elseif item === :GE1
                cf = :(>=(1))
            else
                throw(ArgumentError(lazy"Unrecognized directive `$item` in @params"))
            end
            if isa(type_, Expr) && type_.head === :curly && type_.args[1] === :Vector
                item = :(@argcheck all($cf, $var))
            else
                item = :(@argcheck $cf($var))
            end
        end
        if item.head === :(::) # field with type assertion
            var = item.args[1]
            type_ = item.args[2] # asserted type
            if isa(type_, Expr) && type_.head == :curly
                got_auto = :Auto in type_.args
                got_none = :None in type_.args
            else
                got_auto = false
                got_none = false
            end
            if type_ === :TwirlingOptions ||
               type_ === :DynamicalDecouplingOptions ||
               type_ === :ResilienceOptions ||
               type_ === :EstimatorExecutionOptions ||
               type_ === :SamplerExecutionOptions
                item = :($var::$type_ = $type_())
            else
                item = :($var::Opt{$type_} = nothing)
            end
            fields[i] = item
        end
        if item.head === :macrocall
            validation_body = item.args[3]
            # We don't support both :None and :Auto (but we could)
            if got_auto
                predicates = :(isnothing($var) || isa($var, Auto) || $(validation_body))
            elseif got_none
                predicates = :(isnothing($var) || isa($var, None) || $(validation_body))
            else
                predicates = :(isnothing($var) || $(validation_body))
            end
            item.args[3] = predicates
            # Add another argument to the validation macro.
            # Because the rewritten predicate is complicated, we have to do this "by hand"
            push!(item.args, :(@got_val $var))
            fields[i] = item
        end
    end
    struct_body.args = fields
    convdef = :(Base.convert(::Type{$struct_name}, d::Dict{Symbol,<:Any}) = $struct_name(d))
    dictdef = :($struct_name(dict::Dict{Symbol}) = $struct_name(; dict...))
    return :(
        @with_kw $code; $dictdef; $convdef; @pretty_show($struct_name, nonothing = true); @struct_hash_equal $struct_name
    )
end

"""
    MeasType

How to process and return measurement results.
* `Classified`
* `Kerneled`
* `AvgKerneled`
"""
@sum_type MeasType <: AbstractOptionEnum begin
    Classified
    Kerneled
    AvgKerneled
end

#! format: off

@params struct SamplerExecutionOptions
    init_qubits::Bool
    rep_delay::Float64; GE0
    meas_type::MeasType
end

"Which dynamical decoupling sequence to use"
@sum_type DDSequenceType <: AbstractOptionEnum begin
    XX
    XpXm
    XY4
end

conversion_case(::DDSequenceType) = SameCase()

"Where to put extra timing delays due to rounding issues"
@sum_type ExtraSlackType <: AbstractOptionEnum begin
    Middle
    Edges
end

"""Whether to schedule gates as soon as ("asap") or as late as ("alap") possible"""
@sum_type SchedulingType <: AbstractOptionEnum begin
    ALAP
    ASAP
end

# If the user does not want DD,
# SamplerOptions or EstimatorOptions, have `nothing` for DD.
# If the user *does* want DD, then they include DynamicalDecouplingOptions.
# The field `enable` is then superfluous.
# When decoding a response from the server, we interpret `enable===false` to
# use `nothing`.
@params struct DynamicalDecouplingOptions
    enable::Bool
    sequence_type::DDSequenceType
    extra_slack::ExtraSlackType
    scheduling_type::SchedulingType
    skip_reset::Bool
end

@sum_type TwirlingStrategy <: AbstractOptionEnum begin
    Active
    ActiveCircuit
    ActiveAccum
    All
end

conversion_case(::TwirlingStrategy) = KebabCase()

@params struct TwirlingOptions
    enable_gates::Bool
    enable_measure::Bool
    num_randomizations::Union{Int, Auto}; GT0
    shots_per_randomization::Union{Int, Auto}; GT0
    strategy::TwirlingStrategy
end

# I don't find this in qiskit-ibm-runtime/options/
struct TranspilationOptions
    optimizaton_level::Int # opt. level: valid values {0, 1}
end

@params struct MeasureNoiseLearningOptions
    num_randomizations::Int; GT0
    shots_per_randomization::Union{Int, Auto}; GT0
end

# This may be obsolete
@params struct NoiseLearnerOptions
    max_layers::Union{Int, None}; GE0
    shots_per_randomizaions::Int; GT0
    num_randomizations::Int; GT0
    layer_pair_depths::Vector{Int64}; GE0
    twirling_strategy::TwirlingStrategy
    experimental::Dict
end

@sum_type ExtrapolatorType <: AbstractOptionEnum begin
    Linear
    Exponential
    DoubleExponential
    PolynomialDegree1
    PolynomialDegree2
    PolynomialDegree3
    PolynomialDegree4
    PolynomialDegree5
    PolynomialDegree6
    PolynomialDegree7
    Fallback
end

@sum_type AmplifierType <: AbstractOptionEnum begin
    GateFolding
    GateFoldingFront
    GateFoldingBack
    PEA
end

# FIXME: Validate input
@params struct ZNEOptions
    amplifier::AmplifierType
    extrapolator::Vector{ExtrapolatorType}
    noise_factors::Vector{Float64}; GE1
    extrapolated_noise_factors::Vector{Float64}; GE0
end

# Docs say "auto" will choose gain in [0, 1]. But user can choose higher?
@params struct PECOptions
    max_overhead::Union{Int, None}; GT0
    noise_gain::Union{Float64, Auto}; GE0
end

# Should we be explicit with Int -> Int64 ?
@params struct LayerNoiseOptions
    max_layers::Union{Int, None}; GE0
    shots_per_randomizaions::Int; GT0
    num_randomizations::Int; GT0
    layer_pair_depths::Vector{Int64}; GE0
end

# Python version has an extra dict key telling whether, for example,
# zne is enabled. All zne params may still be present. I think it
# may be simpler and less error prone, to allow the zne options to
# be absent... say `nothing`.
# For now, selecting on or off is not implemented.
"""
    struct ResilienceOptions

Advanced resilience options to fine tune the resilience strategy
"""
@params struct ResilienceOptions
    # Following is redundant, but we can try using it anyway
    # Special cases for this struct is a PITA
    zne_mitigation::Bool
    measure_mitigation::Bool
    # Likewise, following is redundant
    pec_mitigation::Bool
    measure_noise_learning::MeasureNoiseLearningOptions
    #    zne_options::ZNEOptions
    zne::ZNEOptions
    pec_options::PECOptions
    layer_noise::LayerNoiseOptions
    # Not yet implemented
#    layer_noise_model::LayerNoiseModel
end

# ResilienceOptions(; measure_noise_learning::Dict{…}, zne_mitigation::Bool, pec_mitigation::Bool, zne::Dict{…}, measure_mitigation::Bool)

"""
    struct SamplerOptions

#Args
- `default_shots::Opt{Int}`: blah
- `dynamical_decoupling::Opt{Union{DynamicalDecouplingOptions, Bool}}`: If not `false` or `nothing`
   enable dynamical decoupling. If type is `DynamicalDecouplingOptions`, then the options apply,
   otherwise default options are set by the server (?? "server", "remote"..?)
- `twirling`:
"""
@params struct SamplerOptions
    "The default number of shots to use if none are specified in the PUBs"
    default_shots::Int; GT0
#    dynamical_decoupling::Union{DynamicalDecouplingOptions, Bool}
    dynamical_decoupling::DynamicalDecouplingOptions
    execution::SamplerExecutionOptions
    twirling::TwirlingOptions
    experimental::Dict
end

function Base.convert(::Type{Union{Bool, DynamicalDecouplingOptions}}, d::Dict{Symbol})
    convert(DynamicalDecouplingOptions, d)
end

# OBSOLETE We do not use the field `enable` in dynamical_decouping.
# If options for this are present, it is enabled.
# function post_process_options(::SamplerOptions, dict)
#     # haskey(dict, :dynamical_decoupling) || return dict
#     # enable_key = :enable
#     # dd = dict[:dynamical_decoupling]
#     # if isa(dd, Bool)
#     #     dict[:dynamical_decoupling] = dd ? Dict(enable_key => true) : nothing
#     # elseif !isnothing(dd)
#     #     dd[enable_key] = true
#     # end
#     return dict
# end

@params struct EstimatorExecutionOptions
    init_qubits::Bool
    rep_delay::Float64; GE0
end

@params struct EstimatorOptions
    default_precision::Float64; GT0
    default_shots::Union{Int, None}; GE0
    resilience_level::Int; @argcheck resilience_level in (0, 1, 2)
    seed_estimator::Int
    dynamical_decoupling::DynamicalDecouplingOptions
    resilience::ResilienceOptions
    execution::EstimatorExecutionOptions
    twirling::TwirlingOptions
    experimental::Dict
    # Following is in schema, but not Python client
#    transpilation::TranspilationOptions
end

# Some fields not implemented yet
@params struct SimulatorOptions
    #    noise_model::NoiseModel
    seed_simulator::Int
    #    coupling_map::CouplingMap
#    basis_gates::BasisGates
end

end # module Options
