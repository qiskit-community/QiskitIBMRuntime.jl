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
    module QiskitRuntime

`QiskitRuntime` is a client for the [Qiskit Runtime REST API](https://docs.quantum.ibm.com/api/runtime) written in the Julia language.

`QiskitRuntime` is analagous to the Python-language client [qiskit-ibm-runtime](https://github.com/Qiskit/qiskit-ibm-runtime).

!!! warning

    `QiskitRuntime` is very new, incomplete, and API-unstable.

    `QiskitRuntime.jl` is *completely unsupported*. No person or entity is responsible for providing any support to users of this software.

# Accounts

Many functions, such as `job`, `jobs`, `user` take an optional argument `account`. If
`account` is omitted, then information will be taken from the user's credentials file
`~/.qisit/qiskit-ibm.json`, or environment variables. The environment variables will be
preferred. See [`Accounts.QuantumAccount`](@ref).

# Layers

There are more or less two layers: An interface to the REST API, and a layer on top that returns data of native and custom
Julia types.

# Caching

Caching is done at the level of entire REST API responses.

Reponses from several endpoints are cached automatically. They can be updated with `refresh=true`. For example
`Requests.job(job_id; refresh=true)`.

Functions in the upper layer also take the keyword argument `refresh` and pass it to the `Requests` layer. For example
`Jobs.job(job_id; refresh=true)`.

Caching is done by dumping the REST responses via JSON3 in `~/.qiskit/runtime_cache/`.
"""
module QiskitRuntime

include("utils/utils.jl")
#include("utils/struct_dicts.jl")
include("utils/convert_case.jl")
include("utils/types.jl")
include("env_vars.jl")
include("ids.jl")
include("parameters2.jl")

# Vendored at 6065fab7 from QuantumClifford.jl
include("quantum_info/pauli_operators.jl")
#include("quantum_info/pauli_strings.jl")
include("npz2.jl")
include("bitarraysx.jl")
include("circuits.jl")
include("containers/primitiveresults.jl")
include("options.jl")
include("decoding.jl")
include("json.jl")
include("pubs.jl")
include("instances.jl")
include("accounts.jl")
include("requests.jl")
include("backends.jl")
include("jobs.jl")

using Reexport: Reexport
include("api.jl")
Reexport.@reexport using .API

# Precompiling is broken in CI because there is no qiskit user dir with cached files.
# Locally use Preferences.jl to control whether precompile happens. See
# https://julialang.github.io/PrecompileTools.jl/stable/#Package-developers:-reducing-the-cost-of-precompilation-during-development
# using MyPackage, Preferences
# set_preferences!(MyPackage, "precompile_workload" => false; force=true)
#
include("precompile.jl")

end # module QiskitRuntime
