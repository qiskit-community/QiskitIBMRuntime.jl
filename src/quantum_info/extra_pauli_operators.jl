# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

#! format: off

(⊗)(l::PauliOperator, r::PauliOperator) = PauliOperator((l.phase[]+r.phase[])&0x3, vcat(xbit(l),xbit(r)), vcat(zbit(l),zbit(r)))

Base.:(*)(l::PauliOperator, r::PauliOperator) = mul_left!(copy(r),l)

function Base.:(*)(l::Number, r::PauliOperator)
    p = copy(r)
    if l==1
        nothing
    elseif l==1im
        p.phase[] = (p.phase[] + 1)&0x3
    elseif l==-1
        p.phase[] = (p.phase[] + 2)&0x3
    elseif l==-1im
        p.phase[] = (p.phase[] + 3)&0x3
    else
        throw(DomainError(l,"Only {±1,±i} are permitted as phases."))
    end
    p
end

Base.:(+)(p::PauliOperator) = p

function Base.:(-)(p::PauliOperator)
    p = copy(p)
    p.phase[] = (p.phase[]+2)&0x3
    p
end

@inline function comm(l::AbstractVector{T}, r::AbstractVector{T})::UInt8 where T<:Unsigned
    res = T(0)
    len = length(l)÷2
    @inbounds @simd for i in 1:len
        res ⊻= (l[i+len] & r[i]) ⊻ (l[i] & r[i+len])
    end
    count_ones(res)&0x1
end

@inline function comm(l::PauliOperator, r::PauliOperator)::UInt8
    comm(l.xz,r.xz)
end
