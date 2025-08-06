# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

using QiskitIBMRuntime
import Dates
using Test
import JSON3

using QiskitIBMRuntime.PrimitiveResults: PrimitiveResult, SamplerPUBResult, DataBin

import QiskitIBMRuntime.BitArraysX: BitArrayAlt

old_user_dir = get_env(:QISKIT_USER_DIR)
set_env!(:QISKIT_USER_DIR, joinpath(pkgdir(QiskitIBMRuntime), "test", ".qiskit"))

try
    include("test_doctests.jl")
    include("test_payloads.jl")
    include("test_qiskit_ibm_runtime.jl")
catch
    throw(ErrorException("tests failed"))
finally
    set_env!(:QISKIT_USER_DIR, old_user_dir)
end

@testset "Verify file headers" begin
    include("../tools/verify_headers.jl")
    @test isempty(find_files_with_header_fault())
end

include("test_aqua.jl")
