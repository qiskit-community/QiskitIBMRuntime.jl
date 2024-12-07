# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.
#using Accessors: @reset

@testset "Test payload" begin
    include("payloads.jl")
    circ = CircuitString(circ_str1)

    thepubs = [SamplerPUB(circ)]

    function make_options()
        topt = TwirlingOptions(;enable_gates=true, num_randomizations=1000)
        ddopt = DynamicalDecouplingOptions(;enable=true)
        return SamplerOptions(;dynamical_decoupling=ddopt, twirling=topt)
#        return SamplerOptions(;twirling=topt, dynamical_decouping=DynamicalDecouplingOptions(;enable=true))
#        return SamplerOptions(;dynamical_decoupling=true, twirling=topt)
    end
    options = make_options()

    import QiskitRuntime.Requests._Requests: _run_job_dict
    thedict = _run_job_dict("ibm_kyiv", thepubs, nothing; options)
    function pretty_string(dict)
        io = IOBuffer()
        JSON3.pretty(io, JSON3.write(thedict))
        String(take!(io))
    end
    rest_string = pretty_string(thedict)

    @test rest_string == payload1
end
