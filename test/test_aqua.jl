# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

using QiskitRuntime
using Aqua: Aqua

import DynamicQuantities


# DynamicQuantities is very greedy with method real estate.
# Due to how Aqua works, I cannot exclude it. I have to exclude a type native to this
# package. If there is more stuff like this, we may have to drop DynamicQuantities.
@testset "aqua test ambiguities QiskitRuntime Core Base" begin
    Aqua.test_ambiguities([QiskitRuntime, Core, Base]; broken=false)
#    Aqua.test_ambiguities([QiskitRuntime, Core, Base]; exclude=[QiskitRuntime.PauliPhases.Phase], broken=false)
end

@testset "aqua unbound_args" begin
    Aqua.test_unbound_args(QiskitRuntime)
end

@testset "aqua undefined exports" begin
    Aqua.test_undefined_exports(QiskitRuntime)
end

@testset "aqua piracies" begin
    Aqua.test_piracies(QiskitRuntime)
end

@testset "aqua project extras" begin
    Aqua.test_project_extras(QiskitRuntime)
end

@testset "aqua state deps" begin
    Aqua.test_stale_deps(QiskitRuntime)
end

@testset "aqua deps compat" begin
    Aqua.test_deps_compat(QiskitRuntime)
end
