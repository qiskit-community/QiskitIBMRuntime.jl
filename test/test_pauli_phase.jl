# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

using QiskitRuntime.PauliStrings: Phase

@testset "Pauli phase" begin

    # Test conststruction
    @test Phase(1) == Phase(0x00)
    @test Phase(im) == Phase(0x01)
    @test Phase(-1) == Phase(0x02)
    @test Phase(-im) == Phase(0x03)

    @test Phase(1.0) == Phase(0x00)
    @test Phase(1.0im) == Phase(0x01)
    @test Phase(-1.0) == Phase(0x02)
    @test Phase(-1.0im) == Phase(0x03)

    @test_throws "Can't convert `1.1` to a Pauli phase" Phase(1.1)
    @test_throws "`0x04` not a valid Pauli phase" Phase(0x04)

    @test Complex(Phase(-im)) === -1im
    @test Complex{Int}(Phase(im)) === Complex{Int}(0, 1)
    @test ComplexF64(Phase(-im)) === 0.0 - 1.0im

    @test real(Phase(1)) == 1
    @test real(Phase(-1)) == -1
    @test real(Phase(im)) == 0
    @test real(Phase(-im)) == 0

    @test imag(Phase(1)) == 0
    @test imag(Phase(-1)) == 0
    @test imag(Phase(im)) == 1
    @test imag(Phase(-im)) == -1

    @test isreal(Phase(1))
    @test isreal(Phase(-1))
    @test !isreal(Phase(im))
    @test !isreal(Phase(-im))

    # tests Base.promote_rule
    @test Phase(Phase(im)) == Phase(im)

    @test Phase(1) .* Phase.((1, im, -1, -im)) == (Phase(+1), Phase(+im), Phase(-1), Phase(-im))
    @test Phase(im) .* Phase.((1, im, -1, -im)) == (Phase(+im), Phase(-1), Phase(-im), Phase(+1))
    @test Phase(-1) .* Phase.((1, im, -1, -im)) == (Phase(-1), Phase(-im), Phase(+1), Phase(+im))
    @test Phase(-im) .* Phase.((1, im, -1, -im)) == (Phase(-im), Phase(+1), Phase(+im), Phase(-1))

    @test complex(Phase(1)) isa Phase
    @test Complex(Phase(1)) isa Complex{Int}

    phases = (Phase(1), Phase(im), Phase(-1), Phase(-im))

    @testset "Inverse $val" for val in phases
        @test inv(val) * val === Phase(1)
        @test val * inv(val) === Phase(1)
    end

    @testset "Equality with Number $val"  for val in phases
        @test val == Complex(val)
    end
    @test Phase(1) == 1
    @test Phase(-1) == -1

    @testset "Conversion with constructor $val" for val in phases
        @testset "type $T" for T in (Complex, Complex{Int}, Complex{Int8}, ComplexF64)
            @test T(val) isa T
            @test T(val) == val
        end
    end
    @testset "Powers of $val" for val in phases
        nr = 4 * 10
        range_ = -nr:nr
        @test [ComplexF64(val)^n for n in range_] == [val^n for n in range_]
        @test inv(val) == inv(Complex(val))
    end

    @test string.(phases) == ("Phase(+1)", "Phase(+im)", "Phase(-1)", "Phase(-im)")
    @test -Phase(1) == Phase(-1)
    @test -Phase(im) == Phase(-im)
    @test -Phase(-1) == Phase(1)
    @test -Phase(-im) == Phase(im)

    @test true * Phase(1) === 1 + 0im
    @test true * Phase(im) === 0 + 1im
    @test false * Phase(1) === 0 + 0im
    @test false * Phase(-1) === 0 + 0im
    @test false * Phase(im) === 0 + 0im

    @test conj(Phase(1)) == Phase(1)
    @test conj(Phase(-1)) == Phase(-1)
    @test conj(Phase(-im)) == Phase(im)
    @test conj(Phase(im)) == Phase(-im)
end
