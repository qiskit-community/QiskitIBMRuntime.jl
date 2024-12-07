# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    # Putting some things in `setup` can reduce the size of the
    # precompile file and potentially make loading faster.
    nothing
    using QiskitRuntime: cached_jobs, results, job, showiter
    @compile_workload begin
        # all calls in this block will be precompiled, regardless of whether
        # they belong to your package or not (on Julia 1.8 and higher)
        @info "Precompiling workload"
        jobids = cached_job_ids()
        jobsall = job.(jobids; refresh=false)
        io = IOBuffer()
        for j in jobsall
            show(io, MIME"text/plain"(), j)
            string(j)
            show(devnull, MIME"text/plain"(), j)
            show(devnull, j)
            print(devnull, j)
        end
        showiter(devnull, jobsall)
        kyiv = backend("ibm_kyiv"; refresh=false)
        # This is cached as well
        # uinf = user_info()
        # show(io, MIME"text/plain"(), uinf)
        # show(io, uinf)
        # string(uinf)
        nothing
    end
end
