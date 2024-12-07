# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

module PrimitiveResults

# structs in this module could be reorganized.

using Dates: Dates
import ..Utils: Utils, @pretty_show
import ..Circuits: CircuitString
import ..PauliOperators: PauliOperator
import ..Ids: JobId

export PrimitiveResult,
    PlainResult,
    SamplerPUBResult,
    PUBResult,
    DataBin,
    Metadata,
    ExecutionSpan,
    LayerError,
    PauliLindbladError

struct Metadata
    fields::Dict{Symbol,Any}
    version::VersionNumber
end

@pretty_show(Metadata)

struct PUBResult
    data
    metadata
end

@pretty_show(PUBResult)

"""
    struct PrimitiveResult{T}

This struct contains job results that were tagged with the type `PrimitiveResults`.

`T` is related to the type of [PUBs](https://docs.quantum.ibm.com/guides/primitive-input-output) in
this container. We currently find values of `PUBResult` and `SamplerPUBResult`. I think the former
may really be used always and only for EstimatorV2 results. But I am not sure.
"""
struct PrimitiveResult{T}
    pub_results::Vector{T}
    metadata::Metadata
    job_id::JobId
end

@pretty_show(PrimitiveResult)

# Some results are not typed. They are a plain dict.
# We make up a name: `PlainResult`

"""
    struct PlainResult

This contains job results that were returned as a `Dict` with two keys, `:results`, and `:metadata`.
I have not yet found documentation on results returned in this form. The struct `PlainResult` is
an ad-hoc way to handle this case.
"""
struct PlainResult
    results
    metadata
    job_id::JobId
end

@pretty_show(PlainResult)

struct SamplerPUBResult
    data
    metadata
end

@pretty_show(SamplerPUBResult)

struct DataBin{T}
    fields::T
end

@pretty_show(DataBin)

struct ExecutionSpan{T}
    start::Dates.DateTime
    stop::Dates.DateTime
    data_slices::T
end

Base.copy(es::ExecutionSpan) = ExecutionSpan(es.start, es.stop, copy(es.data_slices))

struct PauliLindbladError
    generators::Vector{PauliOperator}
    rates::Vector{Float64}
end

@pretty_show(PauliLindbladError)

struct LayerError
    circuit::CircuitString
    error::PauliLindbladError
    qubits::Vector{Int}
end

@pretty_show(LayerError)

struct LayerNoise
    unique_mitigated_layers::Int
    unique_mitigated_layers_noise_overhead::Vector{Float64}
    total_mitigated_layers::Int
    noise_overhead::Float64
end

@pretty_show(LayerNoise)

# This does not work because some fields have no copy constructor.
# I don't see an easy way to get this info without an instance of the obj.
# for T in (PUBResult, DataBin, Metadata, ExecutionSpan)
#     fnames = fieldnames(T)
#     args = Tuple(:(copy(obj.$x)) for x in fnames)
# #    @eval Base.copy(obj::$T) = $T((copy(getfield(obj, name)) for name in $fnames)...)
# end

end # module PrimitiveResults
