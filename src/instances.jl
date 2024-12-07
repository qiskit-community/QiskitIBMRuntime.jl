# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

module Instances

export Instance

struct Instance
    hub::String
    group::String
    project::String
end

module _Instance
function _as_tuple end
end # module _Instance
import ._Instance: _as_tuple

# TODO: There are some tools to do this more generically.
function _as_tuple(instance::Instance)
    (; hub, group, project) = instance
    return (hub, group, project)
end

"""
    Instance(instance::AbstractString)

Construct an `Instance` from a string of the form `"hub/group/project"`.

```jldoctest
julia> inst = Instance("a_hub/a_group/a_project")
Instance(a_hub/a_group/a_project)

julia> inst.project
"a_project"

julia> Instance("a_hub/a_group/a_project/")
ERROR: ArgumentError: Expecting three parts separated by '/'. Got 4 parts
```
"""
function Instance(instance::AbstractString)
    parts = split(instance, '/')
    length(parts) == 3 || throw(
        ArgumentError(
            lazy"Expecting three parts separated by '/'. Got $(length(parts)) parts",
        ),
    )
    (hub, group, project) = parts
    return Instance(hub, group, project)
end

# Don't want pretty show
function Base.show(io::IO, ::MIME"text/plain", instance::Instance)
    return print(io, "Instance(", instance, ")")
end

# FIXM: Check this again. Things have changed since written.
# We use this for desired result in Utils._show
function Base.show(io::IO, instance::Instance)
    return print(io, "Instance(", instance, ")")
end

let
    # Join the parts of `instance` with separator `sep`.
    function _as_string(instance::Instance, sep="/")
        return join(_as_tuple(instance), sep)
    end

    function Base.print(io::IO, instance::Instance)
        return print(io, _as_string(instance))
    end

    global filename_encoded
    # If you include the instance as part of a filename, the slashes will be
    # directory separators. Replace them with underscores.
    function filename_encoded(instance::Instance)
        return _as_string(instance, "_")
    end
end # let

# This allows automatic conversion to `String` when passing `Instance` as a parameter.
# If a function expects a string, passing in instance will work.
# Here `string` falls back to the method for `print` above.
function Base.convert(::Type{String}, instance::Instance)
    return string(instance)
end

end # module Instances
