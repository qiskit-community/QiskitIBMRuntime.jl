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
    module ConvertCase

Holy Traits for string case conversion.
"""
module ConvertCase

export LowerCase, SnakeCase, KebabCase, SameCase, CamelCase, conversion_case, convert_case

"""
    struct LowerCase end

Convert all characters to lower case.
"""
struct LowerCase end

"""
    struct SnakeCase end

Convert to snake case
"""
struct SnakeCase end

struct KebabCase end

"""
    struct SameCase end

Do not convert existing string.
"""
struct SameCase end

struct CamelCase end

conversion_case(::Type{T}) where {T} = SnakeCase()
conversion_case(::T) where {T} = conversion_case(T)

function snake_to_camel(s)::String
    return lowercase(replace(string(s), r"([a-z])([A-Z])" => s"\1_\2"))
end

"""
    snake_to_camel(snake_case::AbstractString; uppercase_first::Bool = true)::String

Convert a `String` from snake case to camel case.

It is assumed that all characters in `snake_case` are lower case ASCII characters, or `'_'`.
"""
function snake_to_camel(snake_case::AbstractString; uppercase_first::Bool=true)::String
    if !occursin("_", snake_case)
        uppercase_first && return uppercasefirst(snake_case)
        return snake_case
    end
    words = split(snake_case, "_")
    if uppercase_first
        return join(uppercasefirst.(words))
    end
    camel_case = join(uppercasefirst.(words[2:end]))
    return words[1] * camel_case
end

function camel_to_snake(s)::String
    return lowercase(replace(string(s), r"([a-z])([A-Z])" => s"\1_\2"))
end

function camel_to_kebab_case(s)::String
    return lowercase(replace(string(s), r"([a-z])([A-Z])" => s"\1-\2"))
end

convert_case(str, ::SnakeCase) = camel_to_snake(string(str))
convert_case(str, ::KebabCase) = camel_to_kebab_case(string(str))
convert_case(str, ::SameCase) = string(str)

end # module ConvertCase
