# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

module JSON

using JSON3

# This will change in upcoming version
# read will be replaced by parse and parsefile.
# At the moment it reads both a file and from a string
function read(str::Union{AbstractString,AbstractVector{UInt8}})
    return JSON3.read(str)
end

function write(dict::AbstractDict)
    return JSON3.write(dict)
end

function write_to_file(filename, json_obj)
    open(filename, "w") do io
        return JSON3.pretty(io, json_obj)
    end
end

# NOTE: This has been fixed on main branch of JSON3
# Ugh.
# JSON3.read tries to interpret a String parameter
# as either JSON or a filename. Because there is no
# good package/culture in Julia for filesytem path objects.
# I have started a package for this. But best to leave that aside
# at the moment.
function read_from_file(filename)
    return JSON3.read(filename)
end

end # module JSON
