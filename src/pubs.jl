# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

module PUBs

export SamplerPUB, EstimatorPUB, AbstractCircuit, CircuitString, QASMString

# internal export
# supports_qiskit

using SumTypes: @sum_type, @cases
using ..Circuits: AbstractCircuit, QASMString, CircuitString
import ..Utils: to_rest_api
using ..Types: Opt
import ..Decode

## Primitive Unified Blocks (PUB)
## https://docs.quantum.ibm.com/guides/primitive-input-output#pubs

### May want to make an AbstractPrimitive, or some other organizational idea.

# May want to parameterize `num_shots` to allow it to be nothing.
# Or use some kind of `Option` type
# http://www.qiskit.org/schemas/sampler_v2_schema.json
# circuit: The quantum circuit in QASM string or base64-encoded QPY format.

# Primitive Unit Bloc of data Each PUB is of the form (Circuit, Parameters, Shots) where
# the circuit is required, parameters should be passed only for parametrized circuits, and
# shots is optional.

# I moved `PrimitiveType` here (from Jobs) to use it. But did not use it.
# I suppose it can stay here.
@sum_type PrimitiveType begin
    EstimatorType
    SamplerType
end

# The conversions here respect the requirements of the REST API: "sampler" and "estimator"
function Base.convert(::Type{PrimitiveType}, str::AbstractString)
    str === "estimator" && return EstimatorType
    str === "sampler" && return SamplerType
    throw(ArgumentError(lazy"Can't convert $(typeof(str)) \"$str\" to `PrimitiveType`"))
end

function Base.convert(::Type{String}, primitive::PrimitiveType)
    @cases primitive begin
        SamplerType => "sampler"
        EstimatorType => "estimator"
    end
end

function Base.string(primitive::PrimitiveType)
    return convert(String, primitive)
end

abstract type AbstractPUB{CircT,ParamsT} end

"""
    SamplerPUB{CircT, ParamsT}

A [PUB](https://docs.quantum.ibm.com/guides/primitive-input-output#pubs) for the Sampler primitive.


    SamplerPUB(circuit, params=nothing, num_shots=nothing)

Create a `SamplerPUB` object.

# Arguments
- `circuit`: The quantum circuit. May be one of...
- `params`: A sequence of circuit angle-parameter sets ...
- `num_shots`: The default number of shots. Works this way...
"""
struct SamplerPUB{CircT<:AbstractCircuit,ParamsT,ST<:Opt{Int}} <: AbstractPUB{CircT,ParamsT}
    _circuit::CircT
    _params::ParamsT
    _num_shots::ST

    function SamplerPUB(circuit, params=nothing, num_shots=nothing)
        !isnothing(num_shots) &&
            num_shots <= 0 &&
            throw(
                ArgumentError(lazy"`num_shots` must be greater than zero. Got $num_shots"),
            )
        return new{typeof(circuit),typeof(params),typeof(num_shots)}(
            circuit,
            params,
            num_shots,
        )
    end
end

# Convert to types that JSON3 knows how to convert to JSON for the REST API.
function to_rest_api(pub::SamplerPUB)
    circstr = to_rest_api(pub._circuit)
    params = isnothing(pub._params) ? [] : pub._params
    if isnothing(pub._num_shots)
        return [circstr, params]
    end
    return [circstr, params, pub._num_shots]
end

# FIXME: Do we want `validate` like the Python version has?
# FIXME: Use one of the struct helper macros in a package. QuickTypes maybe.
# What we have now is pretty verbose.
"""
    EstimatorPUB{CircT, ParamsT}

A [PUB](https://docs.quantum.ibm.com/guides/primitive-input-output#pubs) for the Estimator primitive.
"""
struct EstimatorPUB{CircT<:AbstractCircuit,ParamsT,ObsT} <: AbstractPUB{CircT,ParamsT}
    _circuit::CircT
    _observables::ObsT # a Vector, or do we need general Array?
    _params::ParamsT
    _precision::Float64

    function EstimatorPUB(circuit, observables, params=nothing, precision=0.0)
        precision >= 0 || throw(ArgumentError(lazy"`precision` must be greater than zero"))
        return new{typeof(circuit),typeof(params),typeof(observables)}(
            circuit,
            observables,
            params,
            precision,
        )
    end
end

let
    function _to_rest_api_observables(v::AbstractVector)
        return [_to_rest_api_observables(x) for x in v]
    end

    function _to_rest_api_observables(x)
        return to_rest_api(x)
    end

    global to_rest_api
    # Convert to types that JSON3 knows how to convert to JSON for the REST API.
    function to_rest_api(pub::EstimatorPUB)
        circstr = to_rest_api(pub._circuit)
        params = isnothing(pub._params) ? [] : to_rest_api(pub._params)
        api_obs = _to_rest_api_observables(pub._observables)
        if pub._precision > 0
            return [circstr, api_obs, params, pub._precision]
        end
        return [circstr, api_obs, params]
    end
end #let

to_rest_api(pubs::AbstractVector{<:AbstractPUB}) = map(to_rest_api, pubs)

# Using stack(A; dims=1) would reverse the dimensions (at least of a matrix).
# But this is wrong:
# If we created an array like this, for two Parameters
# A = [[p1(i), p2(i)] for i in 1:100],
# then stack(A) gives a (Julia) 2x100 Matrix
# In `serialize_compress_encode_numpy` we claim it is a C order array, not Fortran.
# Then it will be deserialized as a (100, 2) C order Matrix at the Server.
function to_rest_api(A::Vector{<:Array{T}}) where {T<:Number}
    return to_rest_api(stack(A))
end

function to_rest_api(A::Array{<:Number})
    data = Decode.serialize_compress_encode_numpy(A)
    return Dict("__type__" => "ndarray", "__value__" => data)
end

# FIXME: We need an organized way to implement an internal API
# This function should be in an internal API
supports_qiskit(::Type{<:EstimatorPUB{<:QASMString}}) = false
supports_qiskit(::Type{<:EstimatorPUB{<:CircuitString}}) = true
supports_qiskit(::Type{<:SamplerPUB{<:QASMString}}) = false
supports_qiskit(::Type{<:SamplerPUB{<:CircuitString}}) = true
supports_qiskit(x::AbstractPUB) = supports_qiskit(typeof(x))
supports_qiskit(::AbstractVector{T}) where {T<:AbstractPUB} = supports_qiskit(T)

api_primitive_type(::Type{<:EstimatorPUB}) = "estimator"
api_primitive_type(::Type{<:SamplerPUB}) = "sampler"
api_primitive_type(pub::AbstractPUB) = api_primitive_type(typeof(pub))
api_primitive_type(::AbstractVector{T}) where {T<:AbstractPUB} = api_primitive_type(T)

function supports_qiskit(x::AbstractVector)
    throw(
        ArgumentError(
            lazy"Vector of PUBs must have element type `EstimatorPUB` or SamplerPUB. Got type `$(eltype(x))`",
        ),
    )
end

end # module PUBs
