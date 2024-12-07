# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

module Decode

using Accessors: @set
# UPDATE: I did try vendoring NPZ, removing Zlib and FileIO support.
# But this only improves load and compile time by a small amount.
# Maybe we should revert.
#
# NPZ loads slowly with lots of recompiling. It's by far the slowest loading dependency.
# Much of the time is in loading Zlib. Which may not be necessary.
# We already have CodecZlib as a dependency, and that loads quickly.
# NPZ was started in 2013 and gets little attention. We might vendor and modify it.
#import NPZ
import ..NPZ2 as NPZ
using Dates: Dates
using Base64: Base64
using TranscodingStreams: TranscodingStream
using CodecZlib: GzipDecompressor, ZlibCompressor

import ..Circuits: CircuitString
import ..PauliOperators: PauliOperator
using JSON3: JSON3

import ..Types: Opt
import ..PrimitiveResults:
    PrimitiveResult,
    SamplerPUBResult,
    DataBin,
    Metadata,
    PUBResult,
    ExecutionSpan,
    LayerError,
    LayerNoise,
    PauliLindbladError
import ..BitArraysX

export parse_datetime, try_parse_datetime, decode, serialize_compress_encode_numpy

module _Decode
function _decode_decompress_deserialize_numpy end
function _get_version end
function _version_value end
function _bitarrayalt_from_qiskit_bitarray end
end # module _Decode

import ._Decode:
    _decode_decompress_deserialize_numpy,
    _get_version,
    _version_value,
    _bitarrayalt_from_qiskit_bitarray

# TYPE_MAP is not used at the moment
# const TYPE_MAP = Dict{String, Any}()
# for _type in (:PrimitiveResult,)
#     @eval TYPE_MAP[$(String(_type))] = $_type
# end

### Decoding and encoding could be better organized.

"""
    parse_datetime(datetime_str::AbstractString)

Return a `DateTime` constructed from `datetime_str`. The string
is truncated to 23 characters. The fractional part of the seconds
are truncated to milliseconds.
"""
function parse_datetime(datetime_str::AbstractString)
    if length(datetime_str) > 23
        # Includes milliseconds
        datetime_str = datetime_str[1:23]
    elseif endswith(datetime_str, 'Z') # Need to encode this timezone info somehow, not throw away
        # No milliseconds
        datetime_str = datetime_str[1:(end - 1)]
    end
    return Dates.DateTime(datetime_str)
end

function try_parse_datetime(datetime::Opt{AbstractString})
    isnothing(datetime) && return nothing
    return parse_datetime(datetime)
end

# This is probably slow, but it works.
# Might do it more efficiently
"""
    _decode_decompress_deserialize_numpy(data_str)

Read a numpy array from a base64 encoded `np.save`'d `numpy.array`.

The operations are:
1. Decode. Base 64 decode the `String` `data_str`
2. Uncompress (with zlib) the result
3. Deserialze with NPZ, the equivalent of `numpy.load`.
"""
function _decode_decompress_deserialize_numpy(data_str)
    transcoder = x -> transcode(GzipDecompressor, x)
    return data_str |>
           Base64.base64decode |>
           Vector{UInt8} |>
           transcoder |>
           String |>
           IOBuffer |>
           NPZ.npzreadarray
end

# The following three functions are for diagnostics and
# can be removed soonish.

# function _decode_raw(data_str)
#     transcoder = x -> transcode(GzipDecompressor, x)
#     return data_str |> Base64.base64decode |> Vector{UInt8} |> transcoder |> String
# end
# function _decode_header(data_str)
#     transcoder = x -> transcode(GzipDecompressor, x)
#     return data_str |>
#            Base64.base64decode |>
#            Vector{UInt8} |>
#            transcoder |>
#            String |>
#            IOBuffer |>
#            NPZ.readheader
# end
# function _decode_header_text(data_str)
#     transcoder = x -> transcode(GzipDecompressor, x)
#     return data_str |>
#            Base64.base64decode |>
#            Vector{UInt8} |>
#            transcoder |>
#            String |>
#            IOBuffer |>
#            NPZ.readheader_text
# end

# Using GzipCompressor will cause an error when decompressing on the server
# We must use ZlibCompressor. The Python client, like we, uses defaults.
function serialize_compress_encode_numpy(A::Array)
    buf = IOBuffer()
    # The server requires fortran_order false
    # We added the `fortran_order` option in our vendored fork.
    NPZ.npzwritearray(buf, A; fortran_order=false)
    return Base64.base64encode(transcode(ZlibCompressor, take!(buf)))
end

# This is a "typed" value that we do not yet handle specially.
struct Unhandled
    name::Symbol
    fields
end

is_typed_value(dict) = haskey(dict, :__type__) && haskey(dict, :__value__)

# We expect a version number here, and return v"0" if
# there is none.
function _get_version(dictlike)
    return VersionNumber(get(dictlike, "version", 0))
end

# Set version from number (Integer), using 0 if nothing.
function _version_value(value)
    isnothing(value) && (value = 0)
    return VersionNumber(value)
end

decode(array::JSON3.Array) = map(decode, array)

# FIXME: should only need the method for Number.
decode(x::Number; job_id=nothing) = x
decode(x::Integer; kwargs...) = x
decode(str::AbstractString) = str
decode(v::Vector) = [decode(x) for x in v]
decode(::Nothing; kws...) = nothing

# Value of key modifies decoding
function decode(key::Symbol, value)
    if key === :version
        return (key, _version_value(value))
    end
    if key === :layer_noise
        return (
            key,
            LayerNoise(
                value[:unique_mitigated_layers],
                value[:unique_mitigated_layers_noise_overhead],
                value[:total_mitigated_layers],
                value[:noise_overhead],
            ),
        )
    end
    return (decode(key), decode(value))
end

# Decode is mainly for the REST "results" response.
# Many, but not all, payloads are a dict with two keys, `__type__` and `__value__`.
# The content should be predictable.
function decode(dict::Union{JSON3.Object,Dict}; job_id=nothing)
    # Some things, like Pauli strings don't have the type and value keys.
    if !is_typed_value(dict)
        return Dict(begin
            (k, v) = decode(k, v)
            k => v
        end for (k, v) in dict)
    end
    _type = Symbol(dict[haskey(dict, :__class__) ? :__class__ : :__type__])
    _value = dict[:__value__]
    if _type === :QuantumCircuit
        CircuitString(_value)
    elseif _type === :ndarray
        # Do these three operations to read the stored numpy data.
        _decode_decompress_deserialize_numpy(_value)
    elseif _type === :PrimitiveResult
        metadata = Metadata(decode(_value.metadata), _get_version(_value.metadata))
        PrimitiveResult(decode(_value.pub_results), metadata, job_id)
    elseif _type === :SamplerPubResult
        decode(SamplerPUBResult, _value)
    elseif _type === :PubResult
        decode(PUBResult, _value)
    elseif _type === :DataBin
        fields = _value.fields
        field_names = Symbol.(keys(fields))
        nt = NamedTuple{(field_names...,)}(
            Tuple(decode(fields[name]) for name in field_names),
        )
        DataBin(nt)
    elseif _type === :datetime
        parse_datetime(_value)
    elseif _type === :ExecutionSpanCollection
        decode(_value) # Ignore the name, this will create `Vector{ExecutionSpan}`
    elseif _type === :ExecutionSpan
        decode(ExecutionSpan, _value)
    elseif _type === :BitArray
        # Read the encoded, compressed, serialized numpy data
        array = decode(_value.array)
        num_bits::Int = _value.num_bits
        _bitarrayalt_from_qiskit_bitarray(array, num_bits)
    elseif _type === :PauliList
        map(PauliOperator, _value.data)
    elseif _type === :LayerError
        LayerError(decode(_value.circuit), decode(_value.error), decode(_value.qubits))
    elseif _type === :PauliLindbladError
        PauliLindbladError(decode(_value.generators), decode(_value.rates))
    else
        # This is an encoded typed value, but we don't recognize it.
        # So we return the default JSON3 encoding
        @show Symbol(_type)
        Unhandled(Symbol(_type), decode(dict.__value__))
    end
end

# Assume that `T` has a simple constructor.  Construct `T` from items in
# `values`.  The keys of `values` are ordered. We need to pass contents of `values` in the
# correct order.
function decode(::Type{T}, values) where {T}
    return T((
        begin
            (k, v) = decode(k, v)
            v
        end for (k, v) in values
    )...)
end

# Check if the Symbol should be an integer.
# Return `sym` or the `Int`.
function decode(sym::Symbol)
    str = String(sym)
    if all(isdigit, str)
        # JSON keys are strings. But some are meant to represent numbers.
        return parse(Int, str)
    end
    return sym
end

# Convert data from qiskit `BitArray` (qiskit/primitives/containers/bit_array.py) to a
# native Julia type `..BitArraysX.BitArrayAlt`.
#
# Julia `Base` has a type `BitArray` of arbitrary dimensions that packs bits with no gaps
# (no unused bits) into a `Vector{UInt64}`.
#
# In contrast, the Python `BitArray` is an ndarray of bitstrings: Each string is packed into a
# sequence of bytes just large enough to hold a bit string. For example, a 21-bit string would
# be stored in a sequence of 3 bytes (ie 24-bit). So an array of 21 bits x 10 shots x 15
# experiments (of some kind) would be stored in an nd-array of shape (15, 10, 3). Note that 21
# bits of each 24 are used, so that three bits are unused. When importing the data into Julia,
# we bitreverse each byte and transpose the array (reverse the dimensions). In the example,
# the Julia data is an `Array{UInt8, 3}` of size (3, 10, 15). And the *first* three bits of
# each sequence of three bytes do not encode data. The array is reshaped to a `Vector` of
# length `3 * 10 * 15` before storage in `BitArrayAlt{UInt8, 3}`.
#
# NB `BitArrayAlt` was implemented specifically for this application. It is not a as capable
# as `Base.BitArray`. It would not be difficult to copy the data to a `Base.BitArray`. But this may
# not be necessary. Also, it may be easier to access the data bitstring-wise from `BitArrayAlt`. It
# is unfortunate that, while in Python the high bits are zeroed and unused, in Julia, the low bits are
# unused.
# * `array` is as read _decode_decompress_deserialize_numpy.
function _bitarrayalt_from_qiskit_bitarray(array::Array{UInt8}, num_bits::Integer)
    # Change endianess
    array = bitreverse.(array)

    # Reverse the dimensions
    ndims = length(size(array))
    array = permutedims(array, reverse(1:ndims))

    # Reshape to `Vector` and wrap in `Chunks`.
    chunks = BitArraysX.Chunks(reshape(array, :))

    # Replace the first dimension by the supplied number of bits, `num_bits`.
    # The existing first dimension times 8 must be large enough to accomodate.
    dims = size(array)
    # I think this may be logically redundant with the check in constructor of BitArrayAlt
    # dim1bits = 8 * dims[1]
    # num_bits <= dim1bits ||
    #     throw(DimensionMismatch(lazy"Required number of bits $num_bits too small for first dimension of array in bits $dim1bits")
    new_dims = @set dims[1] = num_bits
    return BitArraysX.BitArrayAlt(chunks, new_dims)
end

end # module Decode
