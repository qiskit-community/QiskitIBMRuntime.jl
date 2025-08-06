# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

"""
    module Ids

This module implements identification numbers and related objects.

`structs` implemented here include: [`JobId`](@ref), [`SessionId`](@ref), [`UserId`](@ref), and [`Ids.Token`](@ref).

!!! note
    We may want to expose less from this module than we do at present. For example, generating bogus
    ids is useful for mocking, but probabaly not for most users.
"""
module Ids

using Random: Random

export AbstractJobId, JobId, SessionId, UserId, Token, validate

function validate end

###
### JobId
###

"""
    abstract type AbstractJobId end

Supertype for `JobId` and `SessionId`.

`JobId` and `SessionId` are wrappers for id strings returned by the Runtime server.
The string length and character set for `JobId` are the same as for `SessionId`.

See [`validate`](@ref), [`SessionId`](@ref), [`JobId`](@ref).
"""
abstract type AbstractJobId end

for Id in (:JobId, :SessionId)
    @eval begin
        struct $Id <: AbstractJobId
            id::String
            function $Id(id::String; check::Bool=true)
                check && validate($Id, id)
                return new(id)
            end
        end
        $Id(id::$Id) = id
        const $(Symbol(Id, :OrString)) = Union{$Id,AbstractString}
    end
end

"""
    struct JobId
    struct SessionId

Wrapper type for job ids and session ids

The data is stored as a string that is validated on construction.

Note that passing validation is a necessary, but not sufficient condition for verifying that a job id
may have been returned by the server. We could investigate the format of job ids and tighten up the validation.

Upon submitting a job with [`QiskitIBMRuntime.Jobs.run_job`](@ref) a job id string is returned.
`JobId` is a wrapper for this string.

Upon initiating a [`QiskitIBMRuntime.Jobs.Batch`](@ref) of jobs, a session id string is returned.
`SessionId` is a wrapper for this string.

See [`validate`](@ref), [`AbstractJobId`](@ref).
"""
JobId, SessionId

#@doc (@doc JobId) SessionId

"""
    validate(::Type{AbstractJobId}, id::AbstractString)

Return `true` if `id` is a valid job or session id.

`id` must be a twenty digit string of `0-9` and `a-z`. There may
be other restrictions, but we don't know about them and cannot check them.

See [`JobId`](@ref), [`SessionId`](@ref).
"""
function validate(T::Type{<:AbstractJobId}, job_id::AbstractString)
    length(job_id) == 20 || error(lazy"$T has incorrect length")
    occursin(r"^[a-z|0-9]+$", job_id) || error(lazy"Illegal character in $T")
    return true
end

# TODO: How to do this docstring
"""
    Random.rand(rng::Random.AbstractRNG, ::Random.SamplerType{JobId})

Return a random `JobId`.

The set of strings sampled is actually larger than that of true job ids.
See [`JobId`](@ref).
"""
Base.rand

# Counting characters in job ids obtained from server gives only
# and all chars in 0:9 and a:z. Some are much more frequenty than
# others. '0' is 8x more frequent that others. We sample the characters
# uniformly.
let (zero_char, nine_char, a_char, z_char) = (48, 57, 97, 122)
    idchars = (Char.(zero_char:nine_char)..., Char.(a_char:z_char)...)
    function Random.rand(
        rng::Random.AbstractRNG,
        ::Random.SamplerType{T},
    ) where {T<:AbstractJobId}
        return T(Random.randstring(rng, idchars, 20); check=false)
    end
end

Base.print(io::IO, id::AbstractJobId) = print(io, id.id)

# It's not clear to me where these are used
Base.convert(::Type{String}, id::AbstractJobId) = string(id)
Base.convert(T::Type{<:AbstractJobId}, id::AbstractString) = T(id)

# For `id * ".json"
Base.:*(id::AbstractJobId, s::String) = string(id) * s
Base.:*(s::String, id::AbstractJobId) = s * string(id)

function Base.isless(a::T, b::T) where {T<:AbstractJobId}
    return isless(a.id, b.id)
end

###
### UserId
###

# I have not seen a schema, so I am guessing based on a few inputs.
# Input strings are 24 hex "digits".

"""
    struct UserId

Wraps a user id.

The server returns 24 hex digits. We encode this as 96 bits in three `UInt32`s.
Thus, validation occurs on construction.
"""
struct UserId
    data::NTuple{3,UInt32}

    function UserId(data::NTuple{3,UInt32})
        return new(data)
    end

    function UserId(str::AbstractString)
        return parse(UserId, str)
    end
end

Base.string(uid::UserId) = join((string(x; base=16, pad=8) for x in uid.data), "")

"""
    Random.rand(rng::Random.AbstractRNG, ::Random.SamplerType{UserId}) =

Construct a random `UserId`.

This is done by generating and wrapping three `UInt32`s.
!!! note
    We may not want to expose this. It is used for mocking data.
"""
Random.rand(rng::Random.AbstractRNG, ::Random.SamplerType{UserId}) =
    UserId(Tuple(rand(rng, UInt32) for _ in 1:3))

# See UUID implementation for more efficient way to do this
# But it uses StringMemory.
function Base.tryparse(::Type{UserId}, str::AbstractString, parsef::F=tryparse) where {F}
    length(str) == 24 || return nothing
    strparts = Tuple(@view str[((i - 1) * 8 + 1):(i * 8)] for i in 1:3)
    nums = (parsef(UInt32, part; base=16) for part in strparts)
    any(isnothing, nums) && return nothing
    return UserId(Tuple(nums))
end

function Base.parse(::Type{UserId}, str::AbstractString)
    length(str) == 24 || throw(ValueError(lazy"UserId must be 24 hex digits"))
    return tryparse(UserId, str, parse)
end

function Base.show(io::IO, id::UserId)
    print(io, typeof(id), "(")
    show(io, string(id))
    return print(io, ")")
end

function Base.print(io::IO, id::UserId)
    return print(io, string(id))
end

###
### Token
###

# We assume the token is just 512 random bits.
"""
    struct Token

Wraps authentication tokens.

The server and the web dashboard express tokens as strings of 128 lower-case hexadecimal
digits. We store this as eight `UInt64`s. In particular, the `Token` is validated upon
construction.

Uppercase hexadecimal characters are allowed when parsing.

```jldoctest
julia> typeof(Token("884fad8b23e0cb2e19ae5df80aab5003e968ea4e3a69c6efce9a776b26cb157bb7456b189a964bdba89423ecb2e7b4d23c2644a672c9ba6ef2a1551bed5879d3"))
Token

julia> Token("abc123")
ERROR: ArgumentError: Token must be 128 hex digits

julia> Token("ABCDAD8B23E0CB2E19AE5DF80AAB5003E968EA4E3A69C6EFCE9A776B26CB157BB7456B189A964BDBA89423ECB2E7B4D23C2644A672C9BA6EF2A1551BED5879D3")
Token("abcdad8b23e0cb2e19ae5df80aab5003e968ea4e3a69c6efce9a776b26cb157bb7456b189a964bdba89423ecb2e7b4d23c2644a672c9ba6ef2a1551bed5879d3")
```
"""
struct Token
    data::NTuple{8,UInt64}

    function Token(data::NTuple{8,UInt64})
        return new(data)
    end

    function Token(str::AbstractString)
        return parse(Token, str)
    end
end

function Base.show(io::IO, tok::Token)
    print(io, typeof(tok), "(")
    show(io, string(tok))
    return print(io, ")")
end

"""
    Random.rand(rng::Random.AbstractRNG, ::Random.SamplerType{Token}) =

Generate a random `Token`.

This might be useful for putting a bogus token in your [credentials file](@ref credentials_file).
"""
Random.rand(rng::Random.AbstractRNG, ::Random.SamplerType{Token}) =
    Token(Tuple(rand(rng, UInt64) for _ in 1:8))

Base.string(token::Token) = join((string(x; base=16, pad=16) for x in token.data), "")

Base.convert(::Type{Token}, id::AbstractString) = Token(id)

function Base.tryparse(::Type{Token}, str::AbstractString, parsef::F=tryparse) where {F}
    strparts = Tuple(@view str[((i - 1) * 16 + 1):(i * 16)] for i in 1:8)
    nums = (parsef(UInt64, part; base=16) for part in strparts)
    any(isnothing, nums) && return nothing
    return Token(Tuple(nums))
end

function Base.parse(::Type{Token}, str::AbstractString)
    length(str) == 128 || throw(ArgumentError(lazy"Token must be 128 hex digits"))
    return tryparse(Token, str, parse)
end

end # module Ids
