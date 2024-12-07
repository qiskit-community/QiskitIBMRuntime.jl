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
    module PauliStrings

Pauli operators represented by `String`s. This is not the most performant way to implement
these. But people often prefer the convenience.
"""
module PauliStrings

export PauliTerm, PauliOp, embed, rand_pauli_string

import ..PauliOperators: PauliOperators, PauliOperator
using Random: Random, AbstractRNG, default_rng

using ..PauliPhases: Phase, phase_from_factors

function embed end

# PauliOperators takes parameters in reverse order to Qiskit
function embed(p::PauliOperator, indices_or_index, num_qubits=length(p))
    return PauliOperators.embed(num_qubits, indices_or_index, p)
end

"""
    struct PauliTerm{T,N}

Represents an `N`-qubit Pauli operator with coefficient of type `T`.

The data is stored as a `String` of `('I','X','Y','Z')` and a coefficient.
The default coefficient type is `Phase`. The coefficient type of
a product (under `*`) of two `PauliTerms` is obtained by promoting the
coefficient types of the operands.
"""
struct PauliTerm{T,N}
    pstring::String
    coeff::T

    function PauliTerm{T}(s::AbstractString, coeff::T) where {T}
        if !all(c -> c in (0x58, 0x59, 0x5a, 0x49), codeunits(s))
            throw(ArgumentError("Unrecognized character in Pauli string"))
        end
        return new{T,length(codeunits(s))}(s, coeff)
    end
end

Base.length(t::PauliTerm{T,N}) where {T,N} = N

function PauliTerm{T,N}(s::AbstractString) where {T,N}
    return PauliTerm{T,N}(s, one(T))
end

"""
    PauliTerm(s::AbstractString, coeff=Phase(1))
    PauliTerm{T,N}(s::AbstractString, coeff::T=one(T)) where {T,N}

Construct an `N`-qubit `PauliTerm`, where `N == length(s)`.
"""
function PauliTerm(s::AbstractString, coeff=Phase(1))
    return PauliTerm{typeof(coeff)}(s, coeff)
end

function Base.:(==)(t1::PauliTerm{<:Any,N}, t2::PauliTerm{<:Any,N}) where {N}
    return codeunits(t1.pstring) == codeunits(t2.pstring) && t1.coeff == t2.coeff
end

# Length differs
Base.:(==)(t1::PauliTerm, t2::PauliTerm) = false

function embed(
    pauli_string::AbstractString,
    indices,
    num_qubits::Integer=length(pauli_string),
)
    lenpauli = length(pauli_string)
    lenpauli != length(indices) && throw(
        ArgumentError(
            lazy"Pauli string length $lenpauli and index list length $(length(indices)) differ.",
        ),
    )
    num_qubits >= lenpauli || throw(
        ArgumentError(
            lazy"num qubits $num_qubits is greater than length of Pauli string $lenpauli",
        ),
    )
    allunique(indices) || throw(ArgumentError("Index list contains duplicate indices."))
    v = fill!(Base.StringMemory(num_qubits), UInt8('I'))
    all(>(0), indices) || throw(ArgumentError("An index is less than one."))
    all(<=(num_qubits), indices) ||
        throw(ArgumentError("An index is greater than num_qubits."))
    for (pos, p) in zip(indices, pauli_string)
        v[pos] = UInt8(p)
    end
    return String(v)
end

function embed(term::PauliTerm, indices, num_qubits=length(term.pstring))
    return PauliTerm(embed(term.pstring, indices, num_qubits), term.coeff)
end

function rand_pauli_string(rng::AbstractRNG, ::Type{String}, n::Integer; coeff::Bool=false)
    coeff && throw(ArgumentError("Pauli string of type `String` has no coefficient"))
    return String(Random.rand!(Base.StringMemory(n), UInt8.(('I', 'X', 'Y', 'Z'))))
end

function rand_pauli_string(::Type{T}, n::Integer; coeff=false) where {T}
    return rand_pauli_string(default_rng(), T, n; coeff)
end
function rand_pauli_string(rng::AbstractRNG, n::Integer; coeff=false)
    return rand_pauli_string(rng, String, n; coeff)
end
rand_pauli_string(n::Integer; coeff=false) = rand_pauli_string(String, n; coeff)

function rand_pauli_string(
    rng::AbstractRNG,
    ::Type{PauliTerm},
    n::Integer;
    coeff::Bool=false,
)
    return rand_pauli_string(rng, PauliTerm{Phase}, n; coeff)
end

function rand_pauli_string(
    rng::AbstractRNG,
    ::Type{PauliTerm{T}},
    n::Integer;
    coeff::Bool=false,
) where {T}
    str = rand_pauli_string(rng, String, n)
    coeff || return PauliTerm{T,n}(str)
    return PauliTerm{T,n}(str, rand(rng, T))
end

struct PauliOp{T,N}
    terms::Vector{PauliTerm{T,N}}

    function PauliOp{T,N}(terms::Vector{PauliTerm{T,N}}) where {T,N}
        return new{T,N}(terms)
    end

    function PauliOp(terms::Vector{PauliTerm{T,N}}) where {T,N}
        return new{T,N}(terms)
    end

    function PauliOp(pstrings, coeffs=nothing)
        if isnothing(coeffs)
            terms = [PauliTerm(p) for p in pstrings]
            t = first(terms)
            return new{typeof(t.coeff),length(t)}(terms)
        else
            terms = [PauliTerm(p, c) for (p, c) in zip(pstrings, coeffs)]
            t = first(terms)
            return new{typeof(t.coeff),length(t)}(terms)
        end
    end
end

PauliOp(t::PauliTerm{T,N}) where {T,N} = PauliOp{T,N}([t])
PauliOp(s::AbstractString) = PauliOp(PauliTerm(s))

Base.getindex(op::PauliOp, ind) = op.terms[ind]

function Base.copy(op::PauliOp{T,N}) where {T,N}
    return PauliOp{T,N}(copy(op.terms))
end

Base.:(==)(op1::PauliOp, op2::PauliOp) = false

function Base.:(==)(op1::PauliOp{<:Any,N}, op2::PauliOp{<:Any,N}) where {N}
    return all(t -> t[1] == t[2], zip(op1.terms, op2.terms))
end

function embed(op::PauliOp, indices, num_qubits=length(term.pstring))
    return PauliOp([embed(term, indices, num_qubits) for term in op.terms])
end

import ..Utils: to_rest_api

# For observables, the coefficient must be real.
# If the API uses Paulis elsewhere, where a complex phase may be needed,
# this will not work. We just take the real part, and trust that the user
# used a real phase.
to_rest_api(p::Phase) = real(p)

function to_rest_api(op::PauliOp)
    return Dict(term.pstring => to_rest_api(term.coeff) for term in op.terms)
end

function _mul(a::Char, b::Char)
    (I, X, Y, Z) = ('I', 'X', 'Y', 'Z')
    i = (true, false)
    mi = (true, true)
    p = (false, false)

    A = (a, b)

    a === b && return (p, I)
    a === I && return (p, b)
    b === I && return (p, a)

    A === (X, Y) && return (i, Z)
    A === (Y, Z) && return (i, X)
    A === (Z, X) && return (i, Y)

    A === (Y, X) && return (mi, Z)
    A === (Z, Y) && return (mi, X)
    A === (X, Z) && return (mi, Y)

    @assert false lazy"Invalid Pauli factors in multiplication $a, $b"
end

# I'm think this is not simd'ed. But I wasn't really convinced one
# way or the other with tests.
# It probably can be done as it is done in QuantumClifford.jl.
# Anyway this is an optimization that can be done later.
function _mul_strings(a::String, b::String)
    (n = ncodeunits(a)) == ncodeunits(b) || throw(ArgumentError("bad"))
    c = Base.StringMemory(n)
    (i_cnt, minus_cnt) = (0, 0)
    @inbounds for j in 1:n
        ((i, minus), val) = _mul(a[j], b[j])
        c[j] = val
        minus_cnt += minus
        i_cnt += i
    end
    phase::Phase = phase_from_factors(i_cnt, minus_cnt)
    return (phase, String(c))
end

function Base.:(*)(p1::PauliTerm{<:Any,N}, p2::PauliTerm{<:Any,N}) where {N}
    phase::Phase, str = _mul_strings(p1.pstring, p2.pstring)
    pm = phase * (p1.coeff * p2.coeff)
    return PauliTerm{typeof(pm),N}(str, pm)
end

# TODO: Reduce common terms
function Base.:(*)(p1::PauliOp{<:Any,N}, p2::PauliOp{<:Any,N}) where {N}
    prods = [a * b for a in p1.terms for b in p2.terms]
    return PauliOp(prods)
end

end # module PauliStrings
