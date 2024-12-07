# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

module Circuits

import ..Utils: to_rest_api
using PauliStrings2: PauliOp, embed

export AbstractCircuitString, CircuitString, QASMString, FinalLayout, apply_layout

abstract type AbstractCircuit end
abstract type AbstractCircuitString <: AbstractCircuit end

"""
    QASMString

OpenQASM 3 program as a `String`.
"""
struct QASMString <: AbstractCircuitString
    data::String
end

"""
    struct CircuitString

Serialized, compressed, encoded data  of Python `QuantumCircuit` type

The `QuantumCircuit` was serialized as qpy, then compressed with zlib, then base64 encoded.
"""
struct CircuitString <: AbstractCircuitString
    data::String
end

function to_rest_api(circ_str::CircuitString)
    return Dict(:__type__ => "QuantumCircuit", :__value__ => string(circ_str))
end

# Truncate printing
function Base.print(io::IO, c::AbstractCircuitString)
    length_limit = 56 # longer strings have middle elided.
    nshow = 25 # number of chars to print at start and end.
    v = c.data
    print(io, typeof(c), "(")
    if length(v) > length_limit
        print(io, @view(v[1:nshow]), " ... ", @view(v[(end - nshow):end]), ")")
    else
        print(io, v, ")")
    end
    return nothing
end

Base.show(io::IO, ::MIME"text/plain", c::AbstractCircuitString) = print(io, c)
Base.show(io::IO, c::AbstractCircuitString) = print(io, c)
Base.string(c::AbstractCircuitString) = c.data

struct FinalLayout
    indices::Vector{Int}
    num_qubits::Int
end

function apply_layout(layout::FinalLayout, op::AbstractString)
    return embed(op, layout.indices, layout.num_qubits)
end

function apply_layout(layout::FinalLayout, op::PauliOp)
    return embed(op, layout.indices, layout.num_qubits)
end

function apply_layout(layout::FinalLayout, v::AbstractVector)
    return [apply_layout(layout, x) for x in v]
end

end # module Circuits
