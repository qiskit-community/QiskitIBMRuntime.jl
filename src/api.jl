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
    module API

This module determines what gets imported if you do `using QiskitRuntime`.

It works by importing the explicitly `export`ed symbols from each of several submodules
and then re-exporting them all. Alternatively, if you `use` one of the submodules, for
example `using QiskitRuntime.Jobs`, then only the symbols exported by that module will be
imported.

Note that submodule `Requests` is special. Its symbols conflict with the symbols exported
by submodules that implement a layer on REST requests. So to get the exported symbols from
`Requests`, you must explicitly do `using QiskitRuntim.Requests`.
"""
module API

using Reexport: Reexport

# Reexport.@reexport using ..QiskitRuntime.Decode
Reexport.@reexport using ..QiskitRuntime.Ids
Reexport.@reexport using ..QiskitRuntime.JSON
Reexport.@reexport using ..QiskitRuntime.Jobs
Reexport.@reexport using ..QiskitRuntime.Accounts
Reexport.@reexport using ..QiskitRuntime.PauliOperators
Reexport.@reexport using ..QiskitRuntime.Backends
Reexport.@reexport using ..QiskitRuntime.PrimitiveResults
Reexport.@reexport using ..QiskitRuntime.Instances
Reexport.@reexport using ..QiskitRuntime.PUBs
Reexport.@reexport using ..QiskitRuntime.Circuits
Reexport.@reexport using ..QiskitRuntime.EnvVars
Reexport.@reexport using ..QiskitRuntime.Options
Reexport.@reexport using ..QiskitRuntime.Types

# Names in Requests and higher layers will conflict. So, we don't import most of these.
# Just a few...
Reexport.@reexport using ..QiskitRuntime.Requests: RuntimeServiceException, Requests

Reexport.@reexport using ..Utils

end #module API
