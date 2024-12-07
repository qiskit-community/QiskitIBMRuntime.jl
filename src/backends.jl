# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

module Backends

using Dates: Dates
using Dictionaries: Dictionary

using StructEquality: @struct_hash_equal
using DynamicQuantities: Units, @us_str, DynamicQuantities
import ..Requests
import ..Utils: Utils, @pretty_show, Iter
import ..Decode
import ..Types: Opt
using ..Parameters2: @with_kw

# using ..Requests: cached_backend_names
# export cached_backend_names

export backends,
    backend_status,
    #    cached_backends,
    least_busy,
    backend,
    backend_properties,
    Nduv,
    backend_configuration,
    backend_defaults

export PhysDim

# Throw assertion error in an unexpected key is in dict-like object
# We do this because data is not homogenous across backends and json objects
# within a backend. And there are changes and bugfixes makde at the server.
function check_keys(d, keylist)
    for k in keys(d)
        @assert k in keylist lazy"Key \"$k\" not expected"
    end
end

function convert_or_nothing(dict, key_, convert_function, default=nothing)
    val = get(dict, key_, default)
    val == nothing && return val
    return convert_function(val)
end

# TODO min_num_qubits
# Several words for one thing: provider == instance = hubgroupproject
"""
    backends(account=nothing; pending=false, testing=false, all=false, instance=nothing, refresh::Opt{Bool}=nothing)

Return a list of names of available backends.

If `pending` is `false`, sort results alphabetically. If `pending` is `true`, sort
by least busy first.

Results are cached.
# Keyword arguments
- `pending`: If `true`, return a list of tuples
   `(name, num_pending_jobs)` sorted by `num_pending_jobs`.
   `pending` sets `refresh` to `true`.
- `testing`: If `true` include test devices, those that begin with `"test_"`.
- `all`: If `true`, return all known backend names, including those unavailable to the user.
   If `all` is `true`, then `instance` is ignored.
- `instance`: Return only names available to instance. If `nothing`, use the default instance
   (taken from the default account info). This may be overriden by `all`.
   then return all backends including those not available to the account.
- `refresh`: If `true`, request names from server. If `false`, use cache only,
   failing if no cached values are found. If `nothing`, prefer cache to server.
   `pending` sets `refresh` to `true`.

See [`least_busy`](@ref)
"""
function backends(
    account=nothing;
    pending::Bool=false,
    testing::Bool=false,
    all::Bool=false,
    instance=nothing,
    refresh::Opt{Bool}=nothing,
)
    pending && (refresh = true) # Fetch names again if we also want num pending jobs
    all && (instance = :all)
    backend_result = Requests.backends(account; provider=instance, refresh)
    # Several names are duplicated. I don't know why. We only need each name once.
    backend_names = sort!(unique(backend_result.devices))
    if !testing
        backend_names = filter(!startswith("test_"), backend_names)
    end
    pending || return backend_names
    pending_jobs = [backend_status(b).pending_jobs for b in backend_names]
    names_pending = collect(zip(backend_names, pending_jobs))
    sort!(names_pending; lt=(x, y) -> x[2] < y[2])
    return names_pending
end

# Redundant
# function cached_backends()
#     return Iter{Backend}(backend(name) for name in Requests.cached_backend_names())
# end

"""
    least_busy(account=nothing; testing=false, instance=nothing)

Return the name of the least busy backend available to `instance`.

See [`backends`](@ref)
"""
function least_busy(account=nothing; testing=false, instance=nothing)
    bkends = backends(account; pending=true, testing, instance)
    return first(first(bkends))
end

@struct_hash_equal struct BackendStatus
    backend_version::Opt{VersionNumber}
    operational::Bool
    pending_jobs::Int
    status_msg::String
end

Utils.@pretty_show(BackendStatus)

"""
    backend_status(backend_name::AbstractString, account=nothing)

Return status information of `backend_name`.
"""
function backend_status(backend_name::AbstractString, account=nothing)
    st = Requests.backend_status(backend_name, account)
    version = isempty(st.backend_version) ? nothing : VersionNumber(st.backend_version)
    return BackendStatus(
        # st.backend_name,
        version,
        st.state, # operational
        st.length_queue, # pending_jobs
        st.message,
    )
end

const UNIT_TRANSLATION =
    Dict("ns" => us"ns", "GHz" => us"GHz", "us" => us"μs", "" => (us"m" / us"m"))

"""
    struct Nduv{T}

Represents a name-date-unit-value. A named, dated, unitful, value.
"""
@struct_hash_equal struct Nduv{T}
    name::String
    value::T
    date::Dates.DateTime
end

function Base.copy(n::Nduv)
    return Nduv(n.name, copy(n.value), n.date)
end

const PhysDim = DynamicQuantities.Quantity{
    Float64,
    DynamicQuantities.SymbolicDimensions{DynamicQuantities.FixedRational{Int32,25200}},
}
# This causes a lot of invalidations
function Base.show(io::IO, ::Type{T}) where {T<:PhysDim}
    return print(io, "PhysDim")
end

function Nduv(dict)
    (; name, value, unit, date) = dict
    return Nduv(name, make_unitful(value, unit), Decode.parse_datetime(date))
end

let
    function _simple_print(io::IO, n::Nduv)
        print(io, "Nduv(")
        fnames = fieldnames(typeof(n))
        for (i, f) in enumerate(fnames)
            print(io, f, " = ", getfield(n, f))
            if i < length(fnames)
                print(io, ", ")
            end
        end
        return print(io, ")")
    end
    # This show method should change `print` as well.
    Base.show(io::IO, n::Nduv) = _simple_print(io, n)
    Base.show(io::IO, ::MIME"text/plain", n::Nduv) = _simple_print(io, n)
end

function make_unitful(val, unit_name)
    unit = get(UNIT_TRANSLATION, unit_name, nothing)
    isnothing(unit) && throw(ArgumentError(lazy"Unsupported unit name \"$unit_name\""))
    return val * unit
end

@struct_hash_equal struct QList
    name::String
    qubits::Vector{Int}
end

for sym in (:length, :getindex, :lastindex, :firstindex)
    @eval Base.$sym(q::QList, args...) = Base.$sym(q.qubits, args...)
end

@struct_hash_equal struct GateProperties
    gate::String
    name::String
    parameters::Vector{Nduv{PhysDim}}
    qubits::Vector{Int}
end

@pretty_show GateProperties

@struct_hash_equal struct BackendProperties
    name::String
    version::VersionNumber
    last_update_date::Dates.DateTime
    qubits::Vector{Vector{Nduv{PhysDim}}}
    general::Vector{Nduv{PhysDim}}
    general_qlists::Vector{QList}
    gates::Vector{GateProperties}
end

Base.print(io::IO, b::BackendProperties) = print(io, typeof(b), "(", b.name, ")")
Base.show(io::IO, ::MIME"text/plain", b::BackendProperties) = print(io, b)
Base.show(io::IO, b::BackendProperties) = print(io, b)

function backend_properties(backend_name; refresh::Opt{Bool}=nothing)
    props = Requests.backend_properties(backend_name; refresh)

    expected = [
        :backend_name,
        :backend_version,
        :gates,
        :general,
        :general_qlists,
        :last_update_date,
        :qubits,
    ]
    check_keys(props, expected)
    return BackendProperties(
        props.backend_name,
        VersionNumber(props.backend_version),
        Decode.try_parse_datetime(props.last_update_date),
        [map(Nduv, q) for q in props.qubits],
        [Nduv(x) for x in props[:general]],
        [QList(x.name, x.qubits) for x in props.general_qlists],
        [
            begin
                check_keys(x, (:gate, :name, :parameters, :qubits))
                GateProperties(x.gate, x.name, [Nduv(y) for y in x.parameters], x.qubits)
            end for x in props.gates
        ],
    )
end

@struct_hash_equal struct Channel
    operates::@NamedTuple{qubits::Vector{Int}}
    purpose::String
    type::String
end

@struct_hash_equal struct GateConfig
    name::String
    coupling_map::Vector{Vector{Int}}
    parameters::Opt{Vector{Any}}
    qasm_def::Opt{String}
end

function GateConfig(dict)
    check_keys(dict, [:coupling_map, :name, :parameters, :qasm_def])
    return GateConfig(
        dict.name,
        [collect(x) for x in dict.coupling_map],
        isnothing(dict.parameters) ? dict.parameters : Any[x for x in dict.parameters],
        dict.qasm_def,
    )
end

@struct_hash_equal struct Hamiltonian
    description::String
    h_latex::String
    h_str::Vector{String}
    osc::Any
    qub::Dictionary{Int,Int}
    vars::Dictionary{Symbol,Float64}
end

function Hamiltonian(dict)
    check_keys(dict, [:description, :h_latex, :h_str, :osc, :qub, :vars])
    # Dictionary must be initialized differently. There's probably a more
    # convenient way! We could write a function, but the conversion are particular
    # to the case.
    qub_keys = [parse(Int, string(x)) for x in keys(dict.qub)]
    #    qub_keys = [1,2,3]
    qub_vals = [Int(x) for x in values(dict.qub)]
    #    qub_vals = [1,2,3]
    qub = Dictionary{Int,Int}(qub_keys, qub_vals)

    var_keys = [Symbol(x) for x in keys(dict.vars)]
    var_vals = collect(values(dict.vars))
    vars = Dictionary(var_keys, var_vals)

    return Hamiltonian(
        dict.description,
        dict.h_latex,
        dict.h_str,
        collect(dict.osc),
        qub,
        vars,
    )
end

function backend_configuration(backend_name; refresh::Opt{Bool}=nothing)
    config = Requests.backend_configuration(backend_name; refresh)

    check_keys(
        config,
        [
            :acquisition_latency,
            :allow_q_object,
            :basis_gates,
            :channels,
            :clops,
            :clops_h,
            :clops_v,
            :conditional,
            :conditional_latency,
            :coords,
            :coupling_map,
            :credits_required,
            :default_rep_delay,
            :description,
            :discriminators,
            :dt,
            :dtm,
            :dynamic_reprate_enabled,
            :gates,
            :hamiltonian,
            :local,
            :max_experiments,
            :max_shots,
            :meas_kernels,
            :meas_levels,
            :meas_lo_range,
            :meas_map,
            :measure_esp_enabled,
            :memory,
            :multi_meas_enabled,
            :n_qubits,
            :n_registers,
            :n_uchannels,
            :backend_name,
            :online_date,
            :open_pulse,
            :parallel_compilation,
            :parametric_pulses,
            :processor_type,
            :quantum_volume,
            :qubit_channel_mapping,
            :qubit_lo_range,
            :rep_delay_range,
            :rep_times,
            :sample_name,
            :simulator,
            :supported_features,
            :supported_instructions,
            :timing_constraints,
            :u_channel_lo,
            :uchannels_enabled,
            :url,
            :backend_version,
        ],
    )
    channel_names = collect(keys(config.channels))
    channels_vals = values(config.channels)
    channels_data = [
        begin
            check_keys(x, (:operates, :purpose, :type))
            check_keys(x.operates, (:qubits,))
            Channel((; qubits=x.operates.qubits), x.purpose, x.type)
        end for x in channels_vals
    ]
    channels = Dictionary(channel_names, channels_data)

    clops = (config.clops == "None" ? nothing : config.clops)
    clops_v = (config.clops_v == "None" ? nothing : config.clops_v)
    clops_h = (config.clops_h == "None" ? nothing : config.clops_h)

    _u_channel_lo(dict) = (q=dict.q, scale=collect(dict.scale))

    (_pair, _paircoll, _pairccoll, _stack) = let config = config
        _pair = (key_) -> (key_ => config[key_])
        _paircoll = (key_) -> key_ => collect(config[key_])
        _pairccoll = (key_) -> key_ => [collect(x) for x in config[key_]]
        _stack = (key_) -> (key_ => stack([collect(x) for x in config[key_]]; dims=1))
        (_pair, _paircoll, _pairccoll, _stack)
    end

    if length(keys(config.hamiltonian)) == 1 && isempty(config.hamiltonian.h_latex)
        hamiltonian = nothing
    else
        hamiltonian = Hamiltonian(config.hamiltonian)
    end

    dict = Dict(
        :acquisition_latency => Any[x for x in config.acquisition_latency], # Vector{Any}
        :allow_q_object => config.allow_q_object, # Bool
        :name => config.backend_name, # String
        :version => VersionNumber(config.backend_version),  # VersionNumber
        :basis_gates => [Symbol(x) for x in config.basis_gates], # Vector{Symbol}
        :channels => channels, # Dictionary{Symbol, Channel}
        :clops => clops, # Opt{Int}
        :clops_v => clops, # Opt{Int}
        :clops_h => clops_h, # Opt{Int}
        :conditional => config.conditional, # Bool
        :conditional_latency => Any[x for x in config.conditional_latency],
        _stack(:coords), # Matrix{Int}
        _stack(:coupling_map),  # Matrix{Int}
        :credits_required => config.credits_required, # Bool
        :default_rep_delay => config.default_rep_delay, # Int
        :description => config.description, # String
        :discriminators => collect(config.discriminators), # Vector{String}
        _pair(:dt), # Float64
        _pair(:dtm), # Float64
        _pair(:dynamic_reprate_enabled), # Bool
        :gates => [GateConfig(x) for x in config.gates], # Vector{GateConfig}
        :hamiltonian => hamiltonian,
        :local => config.local, # Bool
        :max_experiments => config.max_experiments, # Int
        :max_shots => config.max_shots, # Int
        :meas_kernels => [Symbol(x) for x in config.meas_kernels], #
        :meas_levels => collect(config.meas_levels), # Vector{Int}
        _stack(:meas_lo_range), # Matrix{Float64}
        _pairccoll(:meas_map), #Vector{Int}
        _pair(:measure_esp_enabled), # Bool
        _pair(:memory), # Bool
        _pair(:multi_meas_enabled),
        _pair(:n_qubits), # int
        _pair(:n_registers), #int
        _pair(:n_uchannels), #int
        :online_date => Decode.try_parse_datetime(config.online_date),
        _pair(:open_pulse), # bool
        _pair(:parallel_compilation), #bool
        _paircoll(:parametric_pulses),
        :processor_type => convert(Dict, config.processor_type),
        _pair(:quantum_volume),
        _pairccoll(:qubit_channel_mapping),
        _stack(:qubit_lo_range), # vec int
        _paircoll(:rep_delay_range), # vec int
        _paircoll(:rep_times), # vec int
        _pair(:sample_name),
        _pair(:simulator),
        _paircoll(:supported_features),
        _paircoll(:supported_instructions),
        :timing_constraints => convert(Dict, config.timing_constraints),
        :uchannel_lo => [[_u_channel_lo(x) for x in y] for y in config.u_channel_lo],
        _pair(:uchannels_enabled),
        :url => config.url === "None" ? nothing : config.url,
    )
    return NamedTuple(dict)
end

@with_kw struct PulseParameters
    amp::Tuple{Float64,Float64}
    beta::Opt{Float64}
    duration::Opt{Float64}
    sigma::Int
    width::Int
end

@struct_hash_equal PulseParameters

function PulseParameters(dict)
    check_keys(dict, (:amp, :beta, :duration, :sigma, :width))

    return PulseParameters(;
        amp=(dict.amp...,),
        beta=get(dict, :beta, nothing),
        duration=get(dict, :duration, nothing),
        sigma=dict.sigma,
        # Try using 0 as a sentinel, instead of "nothing", etc.
        width=get(dict, :width, 0),
    )
end

# TODO: use @with_kw
struct Pulse
    ch::Opt{String}
    label::Opt{String}
    name::String
    parameters::Opt{PulseParameters}
    pulse_shape::Opt{String}
    duration::Opt{Int}
    memory_slot::Opt{Vector{Int}}
    qubits::Opt{Vector{Int}}
    phase::Opt{Union{Float64,String}}
    t0::Int
end

@struct_hash_equal Pulse

function Pulse(d)
    parameters = get(d, :parameters, nothing)
    isnothing(parameters) || (parameters = PulseParameters(parameters))
    check_keys(
        d,
        (
            :ch,
            :label,
            :name,
            :parameters,
            :pulse_shape,
            :duration,
            :qubits,
            :memory_slot,
            :phase,
            :t0,
        ),
    )
    return Pulse(
        get(d, :ch, nothing),
        get(d, :label, nothing),
        d.name,
        parameters,
        get(d, :pulse_shape, nothing),
        get(d, :duration, nothing),
        convert_or_nothing(d, :memory_slot, collect),
        convert_or_nothing(d, :qubits, collect),
        get(d, :phase, nothing),
        d.t0,
    )
end

struct CmdDef
    name::String
    qubits::Vector{Int}
    sequence::Vector{Pulse}
end

@struct_hash_equal CmdDef

function CmdDef(d)
    return CmdDef(d.name, collect(d.qubits), map(Pulse, d.sequence))
end

@with_kw struct BackendDefaults
    buffer::Int
    cmd_defs::Vector{CmdDef}
    #    discriminator # same on all backends.
    measure_freq_est::Vector{Float64}
    meas_kernel::String # needs params too
    pulse_library::Vector{Any}
    qubit_freq_est::Vector{Float64}
end

@struct_hash_equal BackendDefaults

function backend_defaults(backend_name; refresh::Opt{Bool}=nothing)
    d = Requests.backend_defaults(backend_name; refresh)
    check_keys(
        d,
        (
            :buffer,
            :cmd_def,
            :discriminator,
            :meas_freq_est,
            :meas_kernel,
            :pulse_library,
            :qubit_freq_est,
        ),
    )
    return BackendDefaults(;
        buffer=d.buffer,
        cmd_defs=map(CmdDef, d.cmd_def),
        measure_freq_est=collect(d.meas_freq_est),
        meas_kernel=d.meas_kernel.name,
        pulse_library=collect(d.pulse_library),
        qubit_freq_est=collect(d.qubit_freq_est),
    )
end

struct Backend
    name::String
    properties
    config
    defaults
end

@struct_hash_equal Backend

Base.print(io::IO, b::Backend) = print(io, typeof(b), "(", b.name, ")")
Base.show(io::IO, ::MIME"text/plain", b::Backend) = print(io, b)
Base.show(io::IO, b::Backend) = print(io, b)

"""
    backend(name; refresh::Opt{Bool}=nothing)

Return an object holding information on the backend `name`.
"""
function backend(name; refresh::Opt{Bool}=nothing)
    return Backend(
        name,
        backend_properties(name; refresh),
        backend_configuration(name; refresh),
        backend_defaults(name; refresh),
    )
end

# Better to just have the user user qm()
# function menu_backend_name(
#     account=nothing;
#     pending::Bool=false,
#     testing::Bool=false,
#     all::Bool=false,
#     instance=nothing,
#     refresh::Opt{Bool}=nothing,
# )
#     thebackends = backends(account; pending, testing, all, instance, refresh)
#     return QuickMenus.qm(thebackends)
# end

end # module Backends
