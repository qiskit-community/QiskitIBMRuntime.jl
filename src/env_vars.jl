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
    module EnvVars

Enforce documentation and a safe interface to the environment variables used by
QiskitIBMRuntime.jl

"safe" means that typos in environment variable names will result in immediate run time or compile time
errors.
"""
module EnvVars
using ..Types: Opt

export env_vars, get_env, set_env!

module _EnvVars

# The Python client uses the env var QISKIT_IBM_RUNTIME_API_URL for the authentication
# url, which is usually "https://auth.quantum-computing.ibm.com/api" I find this name
# confusing. So, I call it QISKIT_IBM_AUTH_URL". In any case, we don't use it.

# If a docstring is missing for any of these, QiskitIBMRuntime will fail to compile
const _ENV_VARS = [
    :QISKIT_ACCOUNT_NAME,
    :QISKIT_IBM_AUTH_URL,
    :QISKIT_IBM_CHANNEL,
    :QISKIT_IBM_INSTANCE,
    :QISKIT_IBM_RUNTIME_LOG_LEVEL,
    :QISKIT_IBM_TOKEN,
    :QISKIT_RUNTIME_CACHE_DIR,
    :QISKIT_RUNTIME_DRY_RUN,
    :QISKIT_USER_DIR,
    :QISKIT_IBM_RUNTIME_NO_CACHE,
]

const _var_docs =
    let unused = "Currently unused by QiskitIBMRuntime.jl",
        _var_descr = Dict(
            :QISKIT_ACCOUNT_NAME => "The name of the account in the credentials file to use by default.",
            :QISKIT_IBM_AUTH_URL => "The url used for authentication. $unused",
            :QISKIT_IBM_CHANNEL => "The channel name used only when setting the account via environment variables. $unused",
            :QISKIT_IBM_INSTANCE => "The instance (\"hub/group/project\") used only when setting the account via environment variables.",
            :QISKIT_IBM_RUNTIME_LOG_LEVEL => unused,
            :QISKIT_IBM_TOKEN => "The token, or API key, used only when setting the account via environment variables.",
            :QISKIT_RUNTIME_CACHE_DIR => "The full path of the REST API response cache overriding the default \$HOME/.qiskit/runtime_cache.",
            :QISKIT_RUNTIME_DRY_RUN => "If set, then POST requests return JSON string rather than sending it to server.",
            :QISKIT_USER_DIR => "The directory storing user data for Qiskit Runtime, including credentials and cache.",
            :QISKIT_IBM_RUNTIME_NO_CACHE => "If set, disable reading and writing the cache. Always make requests to the server.",
        )

        _var_doc(varname) = "`$varname`" * " - " * _var_descr[varname]
        join(map(_var_doc, _ENV_VARS), "\n\n")
    end

# Unused at the moment
# :QISKIT_IBM_RUNTIME_LOG_LEVEL

end # module _EnvVars

import ._EnvVars: _ENV_VARS, _var_docs

"""
    get_env(name::Symbol, default=nothing)

Return the value for environment variable `name`, or `default` if `name` is not present.

See [`env_vars`](@ref), [`set_env!`](@ref).

!!! note
    An error is thrown if `name` is not an environment variable used by `QiskitIBMRuntime.jl`.
"""
function get_env(name::Symbol, default=nothing)
    name in _ENV_VARS || throw(
        ArgumentError(lazy"Environment variable `$name` is not used by QiskitIBMRuntime.jl"),
    )
    return get(ENV, string(name), default)
end

"""
    set_env!(name::Symbol, val::Union{AbstractString, Nothing})

Set the value for environment variable `name` to `val`.

If `val` is `nothing`, then `name` is deleted from `Base.ENV`.

See [`env_vars`](@ref), [`get_env`](@ref).

!!! note
    An error is thrown if `name` is not an environment variable used by `QiskitIBMRuntime.jl`.
"""
function set_env!(name::Symbol, val::Opt{AbstractString})
    name in _ENV_VARS || throw(
        ArgumentError(lazy"Environment variable `$name` is not used by QiskitIBMRuntime.jl"),
    )
    sname = string(name)
    if isnothing(val)
        haskey(ENV, sname) && delete!(ENV, sname)
    else
        ENV[sname] = val
    end
    return env_vars()
end

"""
    env_vars()

Return a `Dict` of all environment variables used by QiskitIBMRuntime.jl and their values.

If the environment variable is not set then its value is `nothing` in the returned
`Dict`. Here "not set" means it is not a key in `Base.ENV`.

See [`set_env!`](@ref), [`get_env`](@ref).

# Variables:
$_var_docs
"""
function env_vars()
    return Dict{Symbol,Opt{String}}(var => get_env(var) for var in _ENV_VARS)
end

end # module EnvVars
