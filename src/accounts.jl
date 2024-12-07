# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

module Accounts

import ..Ids: Token
import ..Instances

export QuantumAccount, list_accounts, all_accounts

### NOTE!
## Use terms "credentials file", "qiskit user directory" as consistently as possible.
## Do not use "config", we have no such thing. This logic is confusing and easy to
## forget. We need to minimize confusion.

# Note that Python version essentially hardcodes channel == "ibm_quantum".
# We leave this variable at present.
# I have know idea what type `proxies` might be. So the type is parameterized
# at the moment.
"""
`struct` that stores credentials data for an account."
"""
struct QuantumAccount{PT}
    channel::String
    auth_url::String
    token::Token
    instance::Instances.Instance
    private_endpoint::Bool
    verify::Bool
    proxies::PT
end

module _Accounts

import ...JSON
import ...Instances
import ...Utils
import ...Ids: Token
import ...EnvVars: get_env

import ..QuantumAccount

# We copy the names from the Python client, for the  most part.
# But we add some, omit some, and modify some (!)
const _DEFAULT_QISKIT_USER_DIR = joinpath(homedir(), ".qiskit")
const _DEFAULT_CREDENTIALS_FILENAME = "qiskit-ibm.json"
const _DEFAULT_ACCOUNT_NAME = "default"
const _DEFAULT_ACCOUNT_NAME_IBM_QUANTUM = "default-ibm-quantum"
const _DEFAULT_ACCOUNT_NAME_IBM_CLOUD = "default-ibm-cloud"
const _DEFAULT_CHANNEL_TYPE = "ibm_cloud"
const _IBM_QUANTUM_CHANNEL = "ibm_quantum"
const _CHANNEL_TYPES = [_DEFAULT_CHANNEL_TYPE, "ibm_quantum"]
const _DEFAULT_QISKIT_IBM_AUTH_URL = "https://auth.quantum-computing.ibm.com/api"

Utils.@pretty_show(QuantumAccount)

function QuantumAccount(channel, instance::AbstractString, url, token; kws...)
    return QuantumAccount(channel, Instances.Instance(instance), url, token; kws...)
end

function QuantumAccount(
    channel,
    instance,
    url,
    token;
    private_endpoint::Bool=false,
    verify::Bool=false,
    proxies=nothing,
)
    return QuantumAccount{typeof(proxies)}(
        channel,
        url,
        token,
        instance,
        private_endpoint,
        verify,
        proxies,
    )
end

function _get_credentials_path_json()
    return _get_path_in_qiskit_user_dir(_DEFAULT_CREDENTIALS_FILENAME)
end

function _get_path_in_qiskit_user_dir(components...)
    qiskit_user_dir = get_env(:QISKIT_USER_DIR, _DEFAULT_QISKIT_USER_DIR)
    return joinpath(qiskit_user_dir, components...)
end

# Read JSON from the default credentials file.
# Return the name of the default file and the JSON object
# in a named tuple
function _read_credentials_file()::NamedTuple
    acct_filename = _get_credentials_path_json()
    isfile(acct_filename) || return (filename=acct_filename, accts_json=nothing)
    accts_string = String(read(acct_filename))
    accts_json = try
        JSON.read(accts_string)
    catch e
        if isa(e, MethodError)
            throw(
                ErrorException(
                    LazyString(
                        "Parse error while reading $acct_filename",
                        "\n",
                        "MethodError: $(e.f)\n",
                    ),
                ),
            )
        end
        throw(
            ErrorException(LazyString("Parse error while reading $acct_filename", "\n", e)),
        )
    end
    return (filename=acct_filename, accts_json=accts_json)
end

function _get_account_name(name)
    !isnothing(name) && return name
    name = get_env(:QISKIT_ACCOUNT_NAME)
    isnothing(name) && (name = _DEFAULT_ACCOUNT_NAME_IBM_QUANTUM)
    return name
end

function _read_account_from_credentials_file(account_name=nothing)::NamedTuple
    result = _read_credentials_file()
    isnothing(result.accts_json) && return (filename=result.filename, account=nothing)
    account_name = _get_account_name(account_name)
    account = get(result.accts_json, account_name, nothing)
    isnothing(account) && throw(
        ErrorException(
            lazy"Account \"$account_name\" not found in credentials file \"$(result.filename)\"",
        ),
    )
    account = QuantumAccount(
        account.channel,
        account.instance,
        account.url,
        Token(account.token);
        private_endpoint=account.private_endpoint,
    )
    return (filename=result.filename, account=account)
end

# instance and token must both be present
# This makes no reference to a credentials file
function _get_account_from_env_variables() # ::Union{Nothing, QuantumAccount}
    instance = get_env(:QISKIT_IBM_INSTANCE)
    isnothing(instance) && return nothing
    token = get_env(:QISKIT_IBM_TOKEN)
    isnothing(token) && return nothing
    channel = get_env(:QISKIT_IBM_CHANNEL, _IBM_QUANTUM_CHANNEL)
    auth_url = get_env(:QISKIT_IBM_AUTH_URL, _DEFAULT_QISKIT_IBM_AUTH_URL)
    return QuantumAccount(channel, instance, auth_url, token)
end

end # module _Accounts

import ._Accounts:
    _read_credentials_file,
    _get_account_from_env_variables,
    _read_account_from_credentials_file

"""
    QuantumAccount(account_name=nothing)::QuantumAccount

Return a `struct` with information for making requests to the REST API.

The account argument may be omitted making requests to the server, for
example when calling [`QiskitRuntime.Jobs.job`](@ref).
In these cases, the account will be constructed with the form `QuantumAccount()`.

The following are tried in order, and the first to succeed is returned.

- If `account_name` is not `nothing` then the account with this name is read from
  the credentials file.
- If the account information is specified in enviroment variables `QISKIT_IBM_INSTANCE`
  and `QISKIT_IBM_TOKEN`, then these are used to construct the `QuantumAccount`. The
  credentials file is not read. (And need not exist.)
- If the environment variable `QISKIT_ACCOUNT_NAME` is set, then this account is
  read from the credentials file.
- The default account `"default-ibm-quantum"` is read from the credentials file.

The credentials file is typically `~/.qiskit/qiskit-ibm.json`.

In case the account is constructed from environment variables, the variables
`QISKIT_IBM_CHANNEL`, `QISKIT_IBM_AUTH_URL` may be set as well to override defaults.

# Examples
(The tokens and instances below are invented, and are not related to any real account.)


```jldoctest
julia> accts = list_accounts() # List the accounts in the credentials file.
2-element Vector{String}:
 "default-ibm-quantum"
 "qiskit-other"

julia> QuantumAccount(accts[1]) # Get the first account
QuantumAccount{Nothing}(
  channel = "ibm_quantum",
  auth_url = "https://auth.quantum-computing.ibm.com/api",
  token = Token("de638e834a4925507bf4181220eff41d116a7baabd9a339cc2e8a3be570f6196cec2f3d77aabc773e1ae1e62ba67b3a5a7d0bbe9de015b89ec65692803c547e9"),
  instance = Instance(hub-one/group-one/project-one),
  private_endpoint = false,
  verify = false,
  proxies = nothing
)

julia> QuantumAccount(accts[2]) # Get the second account
QuantumAccount{Nothing}(
  channel = "ibm_quantum",
  auth_url = "https://auth.quantum-computing.ibm.com/api",
  token = Token("726f2418e17c5845aad93c8e8a3cccaa642b9473132aaec47da93cb2f619fe3d156fb4962ebf8865bed278970bbddc3db0caf58c429b2fffd8c8c0359d80b43a"),
  instance = Instance(hub-two/group-two/project-two),
  private_endpoint = false,
  verify = false,
  proxies = nothing
)

julia> QuantumAccount() # Get the default account, "default-ibm-quantum"
QuantumAccount{Nothing}(
  channel = "ibm_quantum",
  auth_url = "https://auth.quantum-computing.ibm.com/api",
  token = Token("de638e834a4925507bf4181220eff41d116a7baabd9a339cc2e8a3be570f6196cec2f3d77aabc773e1ae1e62ba67b3a5a7d0bbe9de015b89ec65692803c547e9"),
  instance = Instance(hub-one/group-one/project-one),
  private_endpoint = false,
  verify = false,
  proxies = nothing
)
```

Using [`QiskitRuntime.EnvVars.set_env!`](@ref), we change the default account name with an environment variable.
 To reduce verbosity, we just show the `instance.`
```jldoctest
julia> set_env!(:QISKIT_ACCOUNT_NAME, "qiskit-other");

julia> QuantumAccount().instance
Instance(hub-two/group-two/project-two)
```

Here we set the account with environment variables, ignoring the credentials file.
```jldoctest
julia> set_env!(:QISKIT_IBM_TOKEN, "f99b2a42c50ef0314434b0a5e60d8eab6b08112dd4259446e7172a34d61c48ea0a1b349e367dd62d7088fc0d0e97948f0d09fe46c4e34dd9550cdee97256e9a8");

julia> set_env!(:QISKIT_IBM_INSTANCE, "a/b/c");

julia> QuantumAccount()
QuantumAccount{Nothing}(
  channel = "ibm_quantum",
  auth_url = "https://auth.quantum-computing.ibm.com/api",
  token = Token("f99b2a42c50ef0314434b0a5e60d8eab6b08112dd4259446e7172a34d61c48ea0a1b349e367dd62d7088fc0d0e97948f0d09fe46c4e34dd9550cdee97256e9a8"),
  instance = Instance(a/b/c),
  private_endpoint = false,
  verify = false,
  proxies = nothing
)

julia> foreach(k -> set_env!(k, nothing), (:QISKIT_IBM_INSTANCE, :QISKIT_IBM_TOKEN, :QISKIT_ACCOUNT_NAME));

```
"""
function QuantumAccount(account_name=nothing)
    if isnothing(account_name) # Only prefer env variables if name is nothing
        account_from_env = _get_account_from_env_variables()
        !isnothing(account_from_env) && return account_from_env
    end
    result = _read_account_from_credentials_file(account_name)
    if isnothing(result.account)
        throw(ErrorException(lazy"User credential file \"$(result.filename)\" not found."))
    end
    return result.account
end

"""
    list_accounts() :: Vector{String}

Return a list of all account names from the user's [credentials file](@ref credentials_file).
"""
function list_accounts()
    result = _read_credentials_file()
    isnothing(result.accts_json) && return nothing
    return string.(keys(result.accts_json))
end

"""
    all_accounts() :: Vector{QuantumAccount}

Return a list of all [`QuantumAccount`](@ref)s in the user's [credentials file](@ref credentials_file).
"""
function all_accounts()::Vector{QuantumAccount}
    acct_names = list_accounts()
    isnothing(acct_names) && return nothing
    return [
        _read_account_from_credentials_file(acct_name).account for acct_name in acct_names
    ]
end

end # module Accounts
