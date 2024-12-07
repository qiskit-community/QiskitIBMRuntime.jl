# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

###
### Vendored at 6065fab7 from QuantumClifford.jl. This files is much faster to
### load than the entire package.  I did not vendor `Tableau`, which is a table of
### PauliOperators. I can do that later if we stick with this representation.
###
# Copyright notice from QuantumClifford.jl
# MIT License
#
# Copyright (c) 2023 Stefan Krastanov
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#! format: off

export @P_str, PauliOperator  # Following are exported in the original ⊗, I, X, Y, Z,

abstract type AbstractOperation end
abstract type AbstractCliffordOperator <: AbstractOperation end

# Disabled because we have not included these capabilities
# julia> pauli4 = 1im * pauli3 ⊗ X
# + XYZX
# julia> Z*X
# +iY

"""
A multi-qubit Pauli operator (``±\\{1,i\\}\\{I,Z,X,Y\\}^{\\otimes n}``).

A Pauli can be constructed with the `P` custom string macro or by building
up one through products and tensor products of smaller operators.

```jldoctest
julia> pauli3 = P"-iXYZ"
-iXYZ
```

We use a typical F(2,2) encoding internally. The X and Z bits are stored
in a single concatenated padded array of UInt chunks of a bit array.

```jldoctest
julia> p = P"-IZXY";


julia> p.xz
2-element Vector{UInt64}:
 0x000000000000000c
 0x000000000000000a
```

You can access the X and Z bits through getters and setters or through the
`xview`, `zview`, `xbit`, and `zbit` functions.

```jldoctest
julia> p = P"XYZ"; p[1]
(true, false)

julia> p[1] = (true, true); p
+ YYZ
```
"""
struct PauliOperator{Tₚ<:AbstractArray{UInt8,0},Tᵥ<:AbstractVector{<:Unsigned}} <:
       AbstractCliffordOperator
    phase::Tₚ
    nqubits::Int
    xz::Tᵥ
end

nqubits(pauli::PauliOperator) = pauli.nqubits

"""Get a view of the X part of the `UInt` array of packed qubits of a given Pauli operator."""
function xview(p::PauliOperator)
    @view p.xz[1:(end ÷ 2)]
end
"""Get a view of the Y part of the `UInt` array of packed qubits of a given Pauli operator."""
function zview(p::PauliOperator)
    @view p.xz[(end ÷ 2 + 1):end]
end
"""Extract as a new bit array the X part of the `UInt` array of packed qubits of a given Pauli operator."""
function xbit(p::PauliOperator)
    one = eltype(p.xz)(1)
    size = sizeof(eltype(p.xz)) * 8
    return [(word >> s) & one == one for word in xview(p) for s in 0:(size - 1)][begin:(p.nqubits)]
end
"""Extract as a new bit array the Z part of the `UInt` array of packed qubits of a given Pauli operator."""
function zbit(p::PauliOperator)
    one = eltype(p.xz)(1)
    size = sizeof(eltype(p.xz)) * 8
    return [(word >> s) & one == one for word in zview(p) for s in 0:(size - 1)][begin:(p.nqubits)]
end

module _PauliOperators

import ..PauliOperator
import ..xbit
import ..zbit

using LinearAlgebra: LinearAlgebra

bitsizeof(::Type{T}) where {T} = sizeof(T) * 8

"""
    log2bitsizeof(::Type{T}) where T

Return base-2 log of the number of bits in the representation of the type `T`.

The value is likely only meaningful for primitive types `T`. The returned value is
compiled constant for each `T`.
"""
@inline @generated function log2bitsizeof(::Type{T}) where {T}
    return :(Int(log2(bitsizeof($T))))
end

@inline _mask(::T) where {T<:Unsigned} = sizeof(T) * 8 - 1
@inline _mask(::Type{T}) where {T<:Unsigned} = sizeof(T) * 8 - 1
@inline _div(T, l) = l >> log2bitsizeof(T)
@inline _mod(T, l) = l & _mask(T)

"""
get_bitmask_idxs(xzs::AbstractArray{<:Unsigned}, i::Int)

Computes bitmask indices for an unsigned integer at index `i`
within the binary structure of a `Tableau` or `PauliOperator`.

For `Tableau`, the method operates on the `.xzs` field, while
for `PauliOperator`, it uses the `.xz` field. It calculates
the following values based on the index `i`:

- `lowbit`, the lowest bit.
- `ibig`, the index of the word containing the bit.
- `ismall`, the position of the bit within the word.
- `ismallm`, a bitmask isolating the specified bit.
"""
@inline function get_bitmask_idxs(xzs::AbstractArray{<:Unsigned}, i::Int)
    T = eltype(xzs)
    lowbit = T(1)
    ibig = _div(T, i - 1) + 1
    ismall = _mod(T, i - 1)
    ismallm = lowbit << ismall
    return lowbit, ibig, ismall, ismallm
end

# Neccesary stuff copied from elsewhere in QuantumClifford.
# Predefined constants representing the permitted phases encoded.
# in the low bits of UInt8.
const _p = 0x00
const _pi = 0x01
const _m = 0x02
const _mi = 0x03

const phasedict = Dict("" => _p, "+" => _p, "i" => _pi, "+i" => _pi, "-" => _m, "-i" => _mi)
const toletter = Dict(
    (false, false) => "_",
    (true, false) => "X",
    (false, true) => "Z",
    (true, true) => "Y",
)

xz2str(x, z) = join(toletter[e] for e in zip(x, z))

function xz2str_limited(x, z, limit=50)
    tupl = collect(zip(x, z))
    n = length(tupl)
    if (ismissing(limit) || limit >= n)
        return xz2str(x, z)
    end
    padding = limit ÷ 2
    return join(toletter[tupl[i]] for i in 1:padding) *
           "⋯" *
           join(toletter[tupl[i]] for i in (n - padding):n)
end

####
#### pauli_operator.jl
####

function PauliOperator(
    phase::UInt8,
    nqubits::Int,
    xz::Tᵥ,
) where {Tᵥ<:AbstractVector{<:Unsigned}}
    return PauliOperator(fill(UInt8(phase), ()), nqubits, xz)
end
function PauliOperator(phase::UInt8, x::AbstractVector{Bool}, z::AbstractVector{Bool})
    phase = fill(UInt8(phase), ())
    xs = reinterpret(UInt, BitVector(x).chunks)::Vector{UInt}
    zs = reinterpret(UInt, BitVector(z).chunks)::Vector{UInt}
    xzs = cat(xs, zs; dims=1)
    return PauliOperator(phase, length(x), xzs)
end
PauliOperator(x::AbstractVector{Bool}, z::AbstractVector{Bool}) = PauliOperator(0x0, x, z)
function PauliOperator(xz::AbstractVector{Bool})
    return PauliOperator(0x0, (@view xz[1:(end ÷ 2)]), (@view xz[(end ÷ 2 + 1):end]))
end

"""
    PauliOperator(str::AbstractString)

Construct a `PauliOperator` from a string representation

# Examples
```jldoctest
julia> PauliOperator("XYZ")
+ XYZ

julia> PauliOperator("-iXYZ")
-iXYZ
```
"""
function PauliOperator(str::AbstractString)
    return _P_str(str)
end

#### Copied from QuantumClifford.jl
####
function _show(io::IO, p::PauliOperator, limit=50)
    return print(
        io,
        ["+ ", "+i", "- ", "-i"][p.phase[] + 1] * xz2str_limited(xbit(p), zbit(p), limit),
    )
end

function Base.show(io::IO, p::PauliOperator)
    if get(io, :compact, false) | haskey(io, :typeinfo)
        _show(io, p, 10)
    elseif get(io, :limit, false)
        sz = displaysize(io)
        _show(io, p, max(2, sz[2] - 7))
    else
        _show(io, p, missing)
    end
end
####

# TODO: This coulde be more efficient
function _P_str(a::Union{String,SubString{String}})
    letters = filter(x -> occursin(x, "_IZXY"), a)
    phase = phasedict[strip(filter(x -> !occursin(x, "_IZXY"), a))]
    return PauliOperator(
        phase,
        [l == 'X' || l == 'Y' for l in letters],
        [l == 'Z' || l == 'Y' for l in letters],
    )
end

function Base.getindex(
    p::PauliOperator{Tₚ,Tᵥ},
    i::Int,
) where {Tₚ,Tᵥₑ<:Unsigned,Tᵥ<:AbstractVector{Tᵥₑ}}
    _, ibig, _, ismallm = get_bitmask_idxs(p.xz, i)
    return ((p.xz[ibig] & ismallm) != 0x0)::Bool,
    ((p.xz[end ÷ 2 + ibig] & ismallm) != 0x0)::Bool
end
function Base.getindex(
    p::PauliOperator{Tₚ,Tᵥ},
    r,
) where {Tₚ,Tᵥₑ<:Unsigned,Tᵥ<:AbstractVector{Tᵥₑ}}
    return PauliOperator(p.phase[], xbit(p)[r], zbit(p)[r])
end

function Base.setindex!(
    p::PauliOperator{Tₚ,Tᵥ},
    (x, z)::Tuple{Bool,Bool},
    i,
) where {Tₚ,Tᵥₑ,Tᵥ<:AbstractVector{Tᵥₑ}}
    _, ibig, _, ismallm = get_bitmask_idxs(p.xz, i)
    if x
        p.xz[ibig] |= ismallm
    else
        p.xz[ibig] &= ~(ismallm)
    end
    if z
        p.xz[end ÷ 2 + ibig] |= ismallm
    else
        p.xz[end ÷ 2 + ibig] &= ~(ismallm)
    end
    return p
end

Base.firstindex(p::PauliOperator) = 1

Base.lastindex(p::PauliOperator) = p.nqubits

Base.eachindex(p::PauliOperator) = 1:(p.nqubits)

Base.size(pauli::PauliOperator) = (pauli.nqubits,)

Base.length(pauli::PauliOperator) = pauli.nqubits

nqubits(pauli::PauliOperator) = pauli.nqubits

function Base.:(==)(l::PauliOperator, r::PauliOperator)
    return r.phase == l.phase && r.nqubits == l.nqubits && r.xz == l.xz
end

Base.hash(p::PauliOperator, h::UInt) = hash(p.phase, hash(p.nqubits, hash(p.xz, h)))

Base.copy(p::PauliOperator) = PauliOperator(copy(p.phase), p.nqubits, copy(p.xz))

function LinearAlgebra.inv(p::PauliOperator)
    ph = p.phase[]
    phin = xor((ph << 1) & ~(UInt8(1) << 2), ph)
    return PauliOperator(phin, p.nqubits, copy(p.xz))
end

function Base.deleteat!(p::PauliOperator, subset)
    p = p[setdiff(1:length(p), subset)]
    return p
end

_nchunks(i::Int, T::Type{<:Unsigned}) = 2 * ((i - 1) ÷ (8 * sizeof(T)) + 1)
function Base.zero(
    ::Type{PauliOperator{Tₚ,Tᵥ}},
    q,
) where {Tₚ,T<:Unsigned,Tᵥ<:AbstractVector{T}}
    return PauliOperator(zeros(UInt8), q, zeros(T, _nchunks(q, T)))
end
Base.zero(::Type{PauliOperator}, q) = zero(PauliOperator{Array{UInt8,0},Vector{UInt}}, q)
Base.zero(p::P) where {P<:PauliOperator} = zero(P, nqubits(p))

"""Zero-out the phases and single-qubit operators in a [`PauliOperator`](@ref)"""
@inline function zero!(
    p::PauliOperator{Tₚ,Tᵥ},
) where {Tₚ,Tᵥₑ<:Unsigned,Tᵥ<:AbstractVector{Tᵥₑ}}
    fill!(p.xz, zero(Tᵥₑ))
    p.phase[] = 0x0
    return p
end

end # module _PauliOperators

import ._PauliOperators: _P_str

macro P_str(a)
    quote
        _P_str($a)
    end
end

# GJL Disabled the doc test.
# We introduced a definition `embed` in a different module (name space).
# After this, the following failed as a jl-doctest, because the other definition
# is used in the test.
"""
Embed a Pauli operator in a larger Pauli operator.

```julia-repl
julia> embed(5, 3, P"-Y")
- __Y__

julia> embed(5, (3,5), P"-YX")
- __Y_X
```
"""
function embed(n::Int, i::Int, p::PauliOperator)
    if nqubits(p) == 1
        pout = zero(typeof(p), n)
        pout[i] = p[1]
        pout.phase[] = p.phase[]
        return pout
    else
        throw(
            ArgumentError(
                """
You are trying to embed a small Pauli operator into a larger Pauli operator.
However, you have not given all the positions at which the operator needs to be embedded.
If you are directly calling `embed`, use the form `embed(nqubits, indices::Tuple, p::PauliOperator)`.
If you are not using `embed` directly, then `embed` must have been incorrectly called
by one of the functions you have called.
""",
            ),
        )
    end
end

function embed(n::Int, indices, p::PauliOperator)
    if nqubits(p) == length(indices)
        pout = zero(typeof(p), n)
        @inbounds @simd for i_ in eachindex(indices)
            i = i_::Int
            pout[indices[i]] = p[i]
        end
        pout.phase[] = p.phase[]
        return pout
    else
        throw(
            ArgumentError(
                lazy"""
You are trying to embed a small Pauli operator into a larger Pauli operator.
However, you have not given all the positions at which the operator needs to be embedded.
The operator you are embedding is of length $(length(p)), but you have specified $(length(indices)) indices.
If you are not using `embed` directly, then `embed` must have been incorrectly called
by one of the functions you have called.
""",
            ),
        )
    end
end
