# (C) Copyright IBM 2025
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

# Usage:
# - find_files_with_header_fault() to list files with missing or misplaced header.
# - add_missing_headers() prepend files with header if missing. This overwrites original files.

# We load the module in order to find the top level directory.
using QiskitIBMRuntime

const THE_PACKAGE = QiskitIBMRuntime
const COPYRIGHT_YEAR_STR = "2025"
const SOURCE_DIRS = ["src", "test", "tools"]
const SOURCE_SUFFIXES = [".jl", ".py"]

const APACHE_TEXT = """
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.
"""

function make_header()
    "# (C) Copyright IBM $COPYRIGHT_YEAR_STR.\n" * APACHE_TEXT * "\n"
end

const NEW_HEADER = make_header()

# Return a list of all Julia source files in `dir_list`
function find_source_files(dir_list = SOURCE_DIRS)
    return collect(Iterators.flatten(
        map(x -> joinpath(p[1], x), filter(x -> any(y->endswith(x, y), SOURCE_SUFFIXES), p[3]))
        for srcdir in dir_list for p in walkdir(joinpath(pkgdir(THE_PACKAGE), srcdir))))
end

struct NoHeader end

struct NotAtTop
    header_line::Int
end

struct HeaderOK end

# Return:
# `NoHeader()` if the header text is not found in contents of `file_path`.
# `NotAtTop(n)` if the header text is found at line `n` with `n>5`.
# `HeaderOk()` otherwise.
function verify_header(file_path)
    text = String(read(file_path))
    location = findfirst(APACHE_TEXT, text)
    isnothing(location) && return NoHeader()
    num_lines = count("\n", @view text[1:location.start])
    num_lines > 5 && return NotAtTop(num_lines)
    return HeaderOK()
end

# Return list of files that do not contain the header
function find_files_with_header_fault(source_files=find_source_files())
    collect(Iterators.filter(x -> x[2] != HeaderOK(), ((path, verify_header(path)) for path in source_files)))
end

function prepend_header(file_path)
    NEW_HEADER * String(read(file_path))
end

# Read `file_path`.
# Write a file with header prepended to `file_path * ".tmp"`.
# Move temp file to original file path.
function write_file_with_header(file_path)
    output_file_path = file_path * ".tmp"
    open(output_file_path, "w") do f
        write(f, prepend_header(file_path))
    end
    rm(file_path)
    cp(output_file_path, file_path)
    rm(output_file_path)
    nothing
end

# Find files with missing headers.
# Add the header to these files.
# Warn about files that do have the header, but too far from the top.
function add_missing_headers()
    bad_header_info = find_files_with_header_fault()
    files_missing_header = collect(map(x -> x[1], Iterators.filter(x -> x[2] == NoHeader(), bad_header_info)))
    num_bad_locations = length(bad_header_info) - length(files_missing_header)
    if num_bad_locations > 0
        @warn lazy"Found $num_bad_locations files with copyright header too far from the top"
    end
    for (i, file_path) in enumerate(files_missing_header)
        @info "writing $file_path"
        write_file_with_header(file_path)
    end
end
