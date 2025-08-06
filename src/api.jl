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

This module determines what gets imported if you do `using QiskitIBMRuntime`.

It works by importing the explicitly `export`ed symbols from each of several submodules
and then re-exporting them all. Alternatively, if you `use` one of the submodules, for
example `using QiskitIBMRuntime.Jobs`, then only the symbols exported by that module will be
imported.

Note that submodule `Requests` is special. Its symbols conflict with the symbols exported
by submodules that implement a layer on REST requests. So to get the exported symbols from
`Requests`, you must explicitly do `using QiskitRuntim.Requests`.
"""
module API

using Reexport: Reexport

# Reexport.@reexport using ..QiskitIBMRuntime.Decode
Reexport.@reexport using ..QiskitIBMRuntime.Ids
Reexport.@reexport using ..QiskitIBMRuntime.JSON
Reexport.@reexport using ..QiskitIBMRuntime.Jobs
Reexport.@reexport using ..QiskitIBMRuntime.Accounts
Reexport.@reexport using ..QiskitIBMRuntime.PauliOperators
Reexport.@reexport using ..QiskitIBMRuntime.Backends
Reexport.@reexport using ..QiskitIBMRuntime.PrimitiveResults
Reexport.@reexport using ..QiskitIBMRuntime.Instances
Reexport.@reexport using ..QiskitIBMRuntime.PUBs
Reexport.@reexport using ..QiskitIBMRuntime.Circuits
Reexport.@reexport using ..QiskitIBMRuntime.EnvVars
Reexport.@reexport using ..QiskitIBMRuntime.Options
Reexport.@reexport using ..QiskitIBMRuntime.Types

# Names in Requests and higher layers will conflict. So, we don't import most of these.
# Just a few...
Reexport.@reexport using ..QiskitIBMRuntime.Requests: RuntimeServiceException, Requests

Reexport.@reexport using ..Utils

end #module API
