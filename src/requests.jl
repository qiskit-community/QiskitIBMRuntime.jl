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
    module Requests

This module manages requests and responses to the REST API.

Several functions in the `Requests` layer make requests to specific endpoints. For some endpoints,
responses are cached as JSON text files.
A request to an endpoint with a cache works as follows:
* A function requesting a specific endpoint is called. For example [`job`](@ref).
  In this case, a job id is passed as a parameter.
* The cached response is looked up by job id. If a cached response is found, it is read, converted to a `JSON3.Object`, and returned.
* If the cached response is not found, a request is
  made to the endpoint. The response string is written to the cache and is also converted to a `JSON3.Object`
  and returned.

If you pass the keyword parameter `refresh=true`, the above scenario is modified.
In this case, the request is sent to the endpoint unconditionally. The cache file, if present,
is overwritten with the new response.

Some endpoints have no associated cache. A function in the `Requests` layer accessing this endpoint
simply makes the requests, parses the result, and returns a `JSON3.Object`.

The following two arguments are common to many functions in the API of the `Requests` layer.

# Arguments
-- `qaccount::Opt{QuantumAccount}=nothing`: The `QuantumAccount` to use. If nothing
    a `QuantumAccount` is created.

# Keyword arguments
-- `refresh::Bool=false`:  If `false`, then a cached response will be preferred. If `true`,
    the a request will be made, and the cache will be updated with a fresh response.

# Options to requests

Many endpoints in the REST API support options, such as filters. Most of these are not yet implemented, although
it is not difficult to do so.

!!! warning
    No measures are taken to protect the cache from corruption in case of errors.
"""
module Requests

using StructEquality: @struct_hash_equal
using Dictionaries: Dictionary

"""
    RuntimeServiceException{T} <: Exception

The exception thrown when the status returned in the response to a GET or POST
request indicates an error.

# Fields
- `status::Int16`: the status code returned in the response
- `body::{<:JSON3.Object}`: The body of the response as a JSON3 object
"""
@struct_hash_equal struct RuntimeServiceException{T} <: Exception
    status::Int16
    body::T
end

function RuntimeServiceException(response)
    return RuntimeServiceException(response.status, JSON.read(response.body))
end

# FIXME: Find a good name for this
@struct_hash_equal struct JobException{T} <: Exception
    status::Int16
    body::T
end

using JSON3: JSON3

@struct_hash_equal struct JobResponse
    response::JSON3.Object
end

function in_final_state(r::JobResponse)
    return !(get_status(r) in ("Running", "Queued"))
end

function get_status(r::JobResponse)
    status = r.response.status
    @assert status in ("Running", "Queued", "Failed", "Completed", "Cancelled") lazy"Unrecognized job status $status"
    return status
end

@struct_hash_equal struct MetricsResponse
    response::JSON3.Object
end

function in_final_state(r::MetricsResponse)
    return haskey(r.response.timestamps, :finished)
end

import ..Types: Opt

module _Requests

using HTTP: HTTP
using URIs: URIs
using JSON3: JSON3
import ...Accounts: QuantumAccount
import ...Accounts
import ...JSON
import ...Circuits: QASMString
import ...Utils
import ...Instances
import ...PUBs
import ...EnvVars: get_env
import ...Types: Opt
import ..RuntimeServiceException
import ..JobException
import ..JobResponse
import ..MetricsResponse

# Hardcoding this allows is to eliminate a struct that carries this with QuantumAccount
const _BASE_REST_URL = URIs.URI("https://api.quantum-computing.ibm.com/runtime")

# Directory names under the top level of cache. These are equal or similar to the
# endpoints from which data was fetched. Files in these directories have names
# "$id.json"
const _CACHE_DIR_NAMES_IDS = (
    "job",
    "job_exclude_params",
    "metrics",
    "results",
    "logs",
    "type",
    "backend_configuration",
    "backend_properties",
    "backend_defaults",
    "sessions",
    "sessions_jobs",
    "tags",
)

# All cache directories. Files in directory "user" are different from those
# in other dirs. They don't contain files named "$id.json".
const _CACHE_DIR_NAMES_ALL = (_CACHE_DIR_NAMES_IDS..., "user", "backends")

# Return the entire url for `endpoint`
function _endpoint_url(endpoint::AbstractString)
    return joinpath(_BASE_REST_URL, endpoint)
end

# Construct a fully qualified cache filename for a response and write the file
# - endpoint: The (possibly modified) endpoint name; used as directory name.
# - response: A JSON3.Object representing the response.
# - id: A string identifying the request. For example a job id.
# - cache_dir: The parent dir to the subdir `endpoint`.
#
# `endpoint` is not really necessarily the endpoint, but something similar.
# Because endpoints do not map perfectly to cache directory tree.
function write_response_cache(endpoint, response, id, cache_dir=nothing)
    isnothing(cache_dir) && (cache_dir = endpoint_cache_directory(endpoint))

    if !isdir(cache_dir)
        mkpath(cache_dir)
    end
    filename = cache_pathname(endpoint, id)
    return JSON.write_to_file(filename, response)
end

"""
    cache_directory()

Return the top-level directory for caching runtime REST requests.

If `QISKIT_RUNTIME_CACHE_DIR` is set, use it.
Otherwise, use the hard-coded value `"~/.qiskit/runtime_cache"`.
"""
function cache_directory()
    let env_cache_dir = get_env(:QISKIT_RUNTIME_CACHE_DIR)
        isnothing(env_cache_dir) || return env_cache_dir
    end
    return Accounts._Accounts._get_path_in_qiskit_user_dir("runtime_cache")
end

"""
    endpoint_cache_directory(endpoint)

Return the fully-qualified path to the cache directory for `endpoint`.
"""
function endpoint_cache_directory(endpoint)
    return joinpath(cache_directory(), endpoint)
end

# Return the fully qualified filename of a cached response.
# The basename is "$id.json". `endpoint` is a label equal to, or similar to,
# the endpoint from which the data was requested.
function cache_pathname(endpoint, id)
    @assert endpoint in _CACHE_DIR_NAMES_ALL lazy"endpoint \"$endpoint\""
    return joinpath(endpoint_cache_directory(endpoint), id * ".json")
end

# Get the id (say job id) from a filename of the form "$id.json".
# Returns SubString
function id_from_json_filename(filename)
    (id, _ext) = split(filename, '.')
    return id
end

# Read and return the cache file associated with `(endpoint, id)` as a JSON object.
# Note that `endpoint` is a label and may not be exactly equal to the name of the endpoint
# from which the cached data was fetched.
function read_response_cache(endpoint, id)
    cache_file = cache_pathname(endpoint, id)
    isfile(cache_file) || return nothing
    return JSON.read_from_file(cache_file)
end

# Unused at the moment
# Return a list of all cache files corresponding to `id`.
# These will in general be found under various endpoints.
# function cache_files_for_id(id)
#     paths = (cache_pathname(endpoint, id) for endpoint in _CACHE_DIR_NAMES_IDS)
#     return collect(Iterators.filter(x -> isfile(x), paths))
# end

# Delete all cache files associated with `id`, typically a job id.
function delete_id_cache_files(id)
    foreach(ep -> delete_cache_file(ep, id; strict=false), _CACHE_DIR_NAMES_IDS)
    return nothing
end

function delete_cache_file(endpoint, id; strict=true)
    cache_file = cache_pathname(endpoint, id)
    if isfile(cache_file)
        strict && throw(ArgumentError(lazy"File \"$cache_file\" not found."))
    else
        return nothing
    end
    rm(cache_file)
    return nothing
end

# headers for GET
function headers_get(qaccount::QuantumAccount)
    token = string(qaccount.token)
    return Dict("Accept" => "application/json", "Authorization" => "Bearer $token")
end

# headers for POST
# We might be able to use the same headers. Need to experiment
function headers_post(qaccount::QuantumAccount)
    token = string(qaccount.token)
    return Dict(
        "Accept" => "application/json",
        "Content-Type" => "application/json",
        "Authorization" => "Bearer $token",
    )
end

function _get_instance(qaccount::QuantumAccount)
    return qaccount.instance
end

# This a small efficiency hack.
# Return (qaccount, instance).
# * If `qaccount` is not nothing, it is returned in the return tuple.
# * If `instance` is not nothing, it is returned in the return tuple.
# * If `qaccount` is nothing, it is created from `QuantumAccount()`
# * If `instance` is nothing it is retrieved from `qaccount`.
#
# We sometimes want to use the default provider (instance),  when `qaccount` was not provided.
# We could create `qaccount` just to extract `instance`.
# But `qaccount` will be created in a downstream call to `GET_request`.
# Here we avoid creating it twice.
# This involves reading the user's credentials file (or ENV variable, etc.)
# It takes about 0.5 ms on my machine.
function _qaccount_instance(qaccount::Opt{QuantumAccount}, instance)
    qaccount = isnothing(qaccount) ? QuantumAccount() : qaccount
    instance = isnothing(instance) ? _get_instance(qaccount) : instance
    return (qaccount, instance)
end

# Filter queries:
# 1. values `nothing` are removed
# 2. `Instance` converted to `String`
# 3. All others passed unchanged.
# Eh, this is a bit clumsy. Things were ok, except we need
# to convert `Instance` to a `String`. But kws are immuatble
# kws = filter(q -> !isnothing(q.second), kws) no longer works
# Note that the provider is also converted to a string
# `query` is `Dict{Symbol, Any}`. If we knew what the allowed
# types are, we could constrain it more.
# We need: String, Integer, Vector of those. And probably other things.
function _filter_request_queries(kws)
    query = Dict{Symbol,Any}()
    for (k, v) in kws
        v === nothing && continue
        isa(v, Integer) && (v = string(v))
        query[k] = (k === :provider ? string(v) : v)
    end
    return query
end

DELETE_request(endpoint, ::Nothing) = DELETE_request(endpoint, QuantumAccount())
function DELETE_request(endpoint::AbstractString, qaccount::QuantumAccount)
    url = _endpoint_url(endpoint)
    response = HTTP.delete(url, headers_get(qaccount); status_exception=false)
    response.status == 204 && return nothing
    throw(RuntimeServiceException(response))
end

PATCH_request(endpoint, ::Nothing; body) = PATCH_request(endpoint, QuantumAccount(); body)
function PATCH_request(endpoint::AbstractString, qaccount::QuantumAccount; body)
    url = _endpoint_url(endpoint)
    response = HTTP.patch(url, headers_get(qaccount), body; status_exception=false)
    response.status == 204 && return nothing
    throw(RuntimeServiceException(response))
end

function GET_request_inner(
    endpoint::AbstractString,
    qaccount::QuantumAccount=QuantumAccount();
    kws...,
)
    url = _endpoint_url(endpoint)
    query = _filter_request_queries(kws)
    return HTTP.get(url, headers_get(qaccount); query=query, status_exception=false)
end

function GET_request_inner(endpoint::AbstractString, ::Nothing; kws...)
    return GET_request_inner(endpoint; kws...)
end

GET_request(endpoint::AbstractString, ::Nothing; kws...) = GET_request(endpoint; kws...)

function GET_request(
    endpoint::AbstractString,
    qaccount::QuantumAccount=QuantumAccount();
    kws...,
)
    response = GET_request_inner(endpoint, qaccount; kws...)
    (; status, body) = response
    # Ugh, interpreting the response is a messy exercise in reverse engineering.
    status == 204 && return nothing  # 204 means ok, but nothing to return
    if status == 404
        # The "results" endpoint sometimes sends 404-- not found
        # The body is indeed JSON. There is a field "message".
        # If the value is "Job is not terminal" this means the results
        # are not yet available, so we return `nothing`.
        # Another way to signal results not yet available is with status code 204
        # which is caught above.
        # Maybe the difference is that if we get 404 it means the job is not
        # finished, but will fail.
        json = JSON.read(body)
        if haskey(json, :errors)
            if json.errors[1].message === "Job is not terminal"
                return nothing
            end
        end
        throw(RuntimeServiceException(response))
    end
    if status == 200
        # The "results" endpoint sometimes sends 200, i.e. OK, even when the job failed
        # (Well, it's not not a server error)
        # The payload is different from all others. It is not JSON.
        # If we try to read as JSON, we get `1` (the few times I've observed)
        # We try to read as JSON. If we get an JSON3.Object, then maybe this really is job results.
        # If we get `1`, then maybe it's not JSON and we simply convert to a string, which
        # is an error message.
        # Then we throw an error with this message.
        json = JSON.read(body)
        if !isa(json, JSON3.Object)
            error_str = String(copy(body))
            throw(JobException(status, error_str))
        end
        # Got status 200, and the result is JSON, so we assume it is really job results.
        return json
    end
    throw(RuntimeServiceException(response))
end
#GET_request(endpoint::AbstractString, ::Nothing; kws...) = GET_request(endpoint; kws...)

# FIXME: check status for errors
function POST_request(
    endpoint::AbstractString,
    body,
    qaccount::QuantumAccount=QuantumAccount(),
)
    if !isnothing(get_env(:QISKIT_RUNTIME_DRY_RUN))
        isnothing(body) && return body
        return Utils.pretty_json(body)
    end
    url = _endpoint_url(endpoint)
    headers = headers_post(qaccount)
    if isnothing(body)
        response = HTTP.post(url; headers, status_exception=false)
        response.status == 204 && return nothing
        throw(RuntimeServiceException(response))
    else
        lasterr = nothing
        for _ in 1:5
            try
                response = HTTP.post(url; body, headers, status_exception=false)
                break
            catch e
                lasterr = e
                @info "post failed, retrying"
            end
            throw(lasterr)
        end
    end
    response.status == 200 || throw(RuntimeServiceException(response))
    return JSON.read(response.body)
end
POST_request(endpoint::AbstractString, body, ::Nothing) = POST_request(endpoint, body)

###
### Jobs
###

# Make a GET request and cache the response, or return an already cached response.
# Positional args:
# - id: a value inserted in an endpoint template. Typically an id.
# - endpoint_cache_dir: Name of subdirectory for caching responses to query.
#   This is typically named something like the static part of the endpoint.
# - get_func: A function that makes a GET request. It is called like: `get_func(id, account)`.
# Keyword args:
# - refresh:
#   If `true`, then unconditionally make request to server. Cache and return response.
#   If `false`, then unconditionally attempt to retrieve response from cache. If the
#   response is not found then: If `strict` is `true`, throw an error. If `strict` is
#   `false`, then return `nothing`.
#   If `nothing`, then try the cache first, and if that fails, make the GET request.
#   Note that the determination that the response does not indicate a final state is
#   made at a higher level, outside of `Request`. If the state is not final, then another
#   call will be made, which will in turn call `_cach_or_query` again.
# - strict: See `request`.
# - cache_name: The base of the filename for storing and retrieving a cached response.
#   If `nothing`, then `cache_name` is set to `id`. The extension ".json" is appendend.
# - kws: A named tuple of keyword args to be passed to the GET request.
#   These are filtered: values of `nothing` are removed. A few transformations are made.
#   See `_filter_request_queries`.
function _cache_or_query(
    id,
    endpoint_cache_dir::AbstractString,
    get_func,
    qaccount=nothing;
    refresh::Opt{Bool}=nothing,
    strict::Bool=true,
    cache_name::Union{String,Nothing}=nothing,
    kws=nothing,
)
    if isnothing(cache_name)
        cache_name = id
    end
    if refresh != true || !isnothing(get_env(:QISKIT_IBM_RUNTIME_NO_CACHE))
        json = read_response_cache(endpoint_cache_dir, cache_name)
        isnothing(json) || return (from_cache=true, json=json)
        if refresh == false
            strict && throw(
                ArgumentError(
                    lazy"No cache found for cache file \"$cache_name\" and endpoint_cache_dir \"$endpoint_cache_dir\".",
                ),
            )
            return nothing
        end
    end
    if isnothing(kws)
        response = get_func(id, qaccount)
    else
        response = get_func(id, qaccount; kws...)
    end
    if !isnothing(response) && isnothing(get_env(:QISKIT_IBM_RUNTIME_NO_CACHE))
        write_response_cache(endpoint_cache_dir, response, cache_name)
    end
    return (from_cache=false, json=response)
end

# Not authorized to perform this action
function admin_metrics(job_id::AbstractString, qaccount=nothing)
    return GET_request("admin/jobs/$job_id/metrics", qaccount)
end

# Not authorized for this
function hub_workloads(qaccount=nothing; instance=nothing)
    if isnothing(instance)
        qaccount = QuantumAccount()
        instance = _get_instance(qaccount)
    end
    return GET_request("workloads/admin", qaccount; instance)
end

# We do this because small text formatting errors produce errors in the html.
function _endpoint(endpoint, url)
    return """
           - [endpoint: `"$endpoint"`](https://docs.quantum.ibm.com/api/runtime/tags/$url)
           """
end

function _add_hub_group_project!(body, instance)
    (hub, group, project) = Instances._as_tuple(instance)
    body[:hub] = hub
    body[:group] = group
    return body[:project] = project
end

# Do work for `run_job`
function _run_job_dict(
    backend_name,
    pubs,
    qaccount=nothing;
    options=nothing,
    support_qiskit=true,
    tags=nothing,
    session_id=nothing,
    log_level=nothing,
)
    backend_name = Utils.normalize_real_name(backend_name)
    qaccount = isnothing(qaccount) ? Accounts.QuantumAccount() : qaccount
    body = Dict{Symbol,Any}()
    isa(pubs, PUBs.AbstractPUB) && (pubs = [pubs])
    _add_hub_group_project!(body, qaccount.instance)
    body[:program_id] = PUBs.api_primitive_type(pubs)
    body[:backend] = backend_name
    !isnothing(tags) && (body[:tags] = tags)
    !isnothing(session_id) && (body[:session_id] = session_id)
    !isnothing(log_level) && (body[:log_level] = log_level)
    params = Dict(
        :pubs => PUBs.to_rest_api(pubs),
        # REST API docs spell this wrong: "supports_qiskit" <--- WRONG
        :support_qiskit => true,
        #  "supports_qiskit" => PUBs.supports_qiskit(pubs), # Documented, but causes unrecognized error
        :version => 2,
    )

    if !isnothing(options)
        params[:options] = PUBs.to_rest_api(options)
    end
    body[:params] = params
    return body
end

end # module _Requests

import ...Circuits: QASMString
import ...Accounts
import ...JSON
import ...Instances: Instances, Instance

import ._Requests:
    _cache_or_query,
    endpoint_cache_directory,
    id_from_json_filename,
    GET_request,
    GET_request_inner,
    POST_request,
    DELETE_request,
    PATCH_request,
    _qaccount_instance,
    _endpoint,
    _BASE_REST_URL,
    _run_job_dict

export job,
    jobs,
    job_ids,
    user_jobs,
    results,
    run_job,
    open_session,
    user_instances,
    user_info,
    workloads,
    backends,
    backend_status,
    backend_configuration,
    backend_defaults,
    RuntimeServiceException

# I don't know how to control Documenter, or the REPL doc systems, as well as I would like
# So the doc strings are here. Users, internal as well, should access these functions from the outer,
# API module. So, when sensible, we actually define the API function out here.
#
# If `exclude_params` is true, we can get the info from one of two cache directories.
# The endpoint cache dir "job" contains params as well, but if we find cache in "job" dir
# we can use it. Extra info will be discarded by the caller.
# We try them sequentially. If they both fail and `refresh` is not `false`, then
# we try the server.
"""
    job(job_id, qaccount=nothing; refresh=nothing)

Retrieve job info for `job_id`.

Returns a named 2-tuple `(from_cache::Bool, json::::JSON3.Object)`. The field `from_cache` is
true if `json` was retrieved from cache.

$(_endpoint("job/{job_id}", "jobs#tags__jobs__operations__GetJobByIdController_getJobById"))
"""
function job(
    job_id,
    qaccount=nothing;
    exclude_params::Bool=false,
    refresh::Opt{Bool}=nothing,
)
    _get_job =
        (job_id, qaccount_=nothing) ->
            GET_request("jobs/$job_id", qaccount_; exclude_params)

    if exclude_params
        if !isnothing(refresh)
            (from_cache, response) =
                _cache_or_query(job_id, "job_exclude_params", _get_job, qaccount; refresh, strict=true)
            return (from_cache, JobResponse(response))
        end
        # First try only job_exclude_params cache
        first_response =
            _cache_or_query(job_id, "job_exclude_params", _get_job, qaccount; refresh=false, strict=false)
        if isnothing(first_response)
            # Found nothing in job_exclude_params cache
            # So try "job" cache
            second_response =
                _cache_or_query(job_id, "job", _get_job, qaccount; refresh=false, strict=false)
            if !isnothing(second_response)
                # "job" cache succeeded
                (from_cache, response) = second_response
            else
                # Go back to job_exclude_params and use server if refresh allows
                third_response = _cache_or_query(job_id, "job_exclude_params", _get_job, qaccount; refresh=refresh, strict=true)
                (from_cache, response) = third_response
            end
        else
            # Found on first try in "job_exclude_params" cache
            (from_cache, response) = first_response
        end
        return (from_cache, JobResponse(response))
    end
    # Don't exclude params, so this is easy.
    (from_cache, response) =
        _cache_or_query(job_id, "job", _get_job, qaccount; refresh, strict=true)
    return (from_cache, JobResponse(response))
end

"""
    user_jobs(qaccount=nothing)::JSON3.Object

Mysterious alternative to `jobs` that returns slightly different results.

$(_endpoint("facade/v1/jobs", "jobs#tags__jobs__operations__listUserJobs"))
"""
function user_jobs(qaccount=nothing)
    return GET_request("facade/v1/jobs", qaccount)
end

# NOTE: The schema of the returned data is slightly different from that returned by
# the function `job`. For this reason, we don't use this when constructing objects
# like `RuntimeJob`..
# TODO: collect and pass filter kwargs
"""
    jobs(qaccount=nothing; tags=nothing)

Return job info on all jobs.

# Keyword arguments

- `tags`:  A list of tags to filter jobs. (The search must match *all* tags?)
- `limit::Opt{Ingeter}`: Number of results to return at a time.
- `offest::Opt{Integer}`: Number of results to offset when retrieving the list of jobs.
- `exclude_params::Opt{Bool}`:  If true, don't include input parameters.
- `pending::Opt{Bool}`: If true, return only jobs not in a final state.
- `instance::Opt{Union{AbstractString,Instance}}` instance to filter jobs. Either
   an `Instance` or a string in format `{hub}/{group}/{project}`.

$(_endpoint("jobs", "jobs#tags__jobs__operations__list_jobs"))
"""
@inline function jobs(
    qaccount=nothing;
    tags=nothing,
    limit::Opt{Integer}=nothing,
    offset::Opt{Integer}=nothing,
    exclude_params::Opt{Bool}=nothing,
    pending::Opt{Bool}=nothing,
    instance::Opt{Union{AbstractString,Instance}}=nothing,
)
    instance = isa(instance, AbstractString) ? Instance(instance) : instance
    return GET_request(
        "jobs",
        qaccount;
        tags,
        limit,
        offset,
        exclude_params,
        pending,
        provider=instance,
    )
end

"""
    job_ids(qaccount=nothing; kws...)

Return an iterator over all job ids as `String`s.

The function [`jobs`](@ref) is called to retrieve the job info
and the ids are extracted and returned. For keyword arguments, see [`jobs`](@ref).
"""
function job_ids(qaccount=nothing; kws...)
    response = jobs(qaccount; kws...)
    return (j.id for j in response.jobs)
end

"""
    cached_job_ids()::Generator{Vector{String}}

Return an iterator over all the job ids associated with cached job info.

These are the ids of jobs that were fetched via [`job`](@ref) or [`jobs`](@ref).
"""
@inline function cached_job_ids()
    cache_dir = endpoint_cache_directory("job")
    filenames = if !isdir(cache_dir)
        return Base.Generator(identity, String[])
    else
        readdir(cache_dir; sort=true)
    end
    substrings = Base.Generator(id_from_json_filename, filenames)
    return Base.Generator(String, substrings)
    # Implemented as above, the type of the `Generator` is more informative.
    # It does not contain gensym'ed function names
    #    return (String(id_from_json_filename(fname)) for fname in filenames)
end

"""
    cached_session_ids()

Return session ids retrieved from cached job info.
"""
function cached_session_ids()
    cache_dir = endpoint_cache_directory("job")
    session_ids = String[]
    filenames = if !isdir(cache_dir)
        session_ids
    else
        readdir(cache_dir; sort=true)
    end
    for filename in filenames
        json = JSON.read_from_file(joinpath(cache_dir, filename))
        session_id = json.session_id
        if isa(session_id, String)
            push!(session_ids, session_id)
        end
    end
    return unique!(session_ids)
end

function cached_job_ids_by_session()
    cache_dir = endpoint_cache_directory("job")
    sessions = Dictionary{String,Vector{String}}()
    filenames = if !isdir(cache_dir)
        return sessions
    else
        readdir(cache_dir; sort=true)
    end
    for filename in filenames
        json = JSON.read_from_file(joinpath(cache_dir, filename))
        session_id = json.session_id
        if isa(session_id, String)
            push!(
                get!(() -> String[], sessions, session_id),
                id_from_json_filename(filename),
            )
        end
    end
    return return sessions
end

# Redundant
# """
#     cached_backend_names()
# Return a list of backend names taken from cached data on backends.
# """
# @inline function cached_backend_names()
#     filenames = String[]
#     for endpoint in ("backend_properties", "backend_configuration", "backend_defaults")
#         cache_dir = endpoint_cache_directory(endpoint)
#         if isdir(cache_dir)
#             filenames_ = readdir(cache_dir; sort=false)
#             append!(filenames, map(String ∘ id_from_json_filename, filenames_))
#         end
#     end
#     return unique!(filenames)
# end

"""
    results(job_id, qaccount=nothing; refresh=nothing)::JSON3.Object

Return the job results for `job_id`.

$(_endpoint("jobs/{job_id}/results", "jobs#tags__jobs__operations__FindJobResultsController_findJobResult"))

The other kind of data on a job, which we call "job info", is retrieved with [`job`](@ref),
or [`jobs`](@ref)
"""
function results(job_id, qaccount=nothing; refresh::Opt{Bool}=nothing)
    _get_results =
        (job_id, account=nothing) -> GET_request("jobs/$job_id/results", qaccount)
    # strict is false because we may need to return `nothing` if nothign is available.
    (_from_cache, json_response) =
        _cache_or_query(job_id, "results", _get_results, qaccount; refresh, strict=false)
    return json_response
end

"""
    metrics(job_id, qaccount=nothing)::JSON3.Object

Return metrics for `job_id`.

$(_endpoint("jobs/{job_id}/metrics", "jobs#tags__jobs__operations__get_job_metrics_jid"))
"""
function metrics(job_id, qaccount=nothing; refresh::Opt{Bool}=nothing)
    _get_metrics =
        (job_id, qaccount=nothing) -> GET_request("jobs/$job_id/metrics", qaccount)
    (from_cache, response) =
        _cache_or_query(job_id, "metrics", _get_metrics, qaccount; refresh)
    return (from_cache, MetricsResponse(response))
end

"""
    transpiled_circuits(job_id, qaccount=nothing)::JSON3.Object

Return transpiled circuits for `job_id`.

$(_endpoint("jobs/{job_id}/transpiled_circuits", "jobs#tags__jobs__operations__get_transpiled_circuits_jid"))
"""
function transpiled_circuits(job_id::AbstractString, qaccount=nothing)
    return GET_request("jobs/$job_id/transpiled_circuits", qaccount)
end

# TODO: We were considering caching this. But the response is pretty fast after the
# first one.
# Provider is the same thing as an instance here, I think
"""
    backends(qaccount=nothing; provider=nothing)::JSON3.Object

Return list of backends available to the configured user and instance.

# Keyword arguments
- `provider`:  May be the name of an instance, `:all`, or `nothing`.
   If `:all`, then return all backends, even those not available
   to the instance. If the name of a provider, return only backends available
   to it. If `nothing`, then take the provider name from the account authenticating
   the request.

I'm pretty sure that "provider" and "instance" mean the same thing.

$(_endpoint("backends", "systems#tags__systems__operations__list_backends"))
"""
function backends(qaccount=nothing; provider=nothing, refresh::Opt{Bool}=nothing)
    # In this package, we use `nothing` to mean it should be filled in later.
    # But the API uses `nothing` to mean "everything".
    if provider === :all
        provider = nothing
    else
        # If either is `nothing`, then fill it in.
        (qaccount, provider) = _qaccount_instance(qaccount, provider)
    end
    # Not yet finished with caching here
    cache_name = isnothing(provider) ? "all" : Instances.filename_encoded(provider)
    _get_item =
        (provider, qaccount=nothing; kws...) -> GET_request("backends", qaccount; kws...)
    kws = (provider=provider,)
    (_from_cache, response) =
        _cache_or_query(cache_name, "backends", _get_item, qaccount; refresh, kws)
    return response
end

###
### Users
###

# Julia has `Base.instances`. So we call this `user_instances`.
"""
    user_instances(qaccount=nothing)::JSON3.Object

Return a list of instances available to the user.

$(_endpoint("instances", "instances#tags__instances__operations__FindInstancesController_findInstances"))
"""
function user_instances(qaccount=nothing)
    return GET_request("instances", qaccount)
end

# In Julia, it's not really hard to get an unexpected performance hit from anonymous functions.
# However, benchmarking shows there is no penalty for semantically creating the anon function
# at runtime.
# The time for  `Jobs.user_info` to call `Requests.user_info` and then populates types `UserInfo`
# and four `InstancePlan`s when the response is cachhed is about 15 μs.
"""
    user_info(qaccount=nothing; refresh=false)::JSON3.Object

Get the authenticated user.

The response includes the user's email and the same information returned by [`user_instances`](@ref).

$(_endpoint("users/me", "users#tags__users__operations__GetUserMeController_getMyUser"))
"""
function user_info(qaccount=nothing; refresh=nothing)
    _user_info = (_dummy, qaccount) -> GET_request("users/me", qaccount)
    # Discard field `from_cache`
    (_from_cache, response) = _cache_or_query("any", "user", _user_info, qaccount; refresh)
    return response
end

"""
    workloads(qaccount=nothing; instance=nothing)::JSON3.Object

List user workloads

* Compared to [`jobs`](@ref), `workloads` returns a smaller dictionary with less information for each job.
* The default filters are different. Not just the limit on the number of returned jobs.

$(_endpoint("workloads/me", "workloads#tags__workloads__operations__FindWorkloadsMeController_findUserWorkloads"))
"""
function workloads(
    qaccount=nothing;
    instance=nothing,
    limit::Integer=nothing,
    backend::AbstractString=nothing,
)
    (qaccount, instance) = _qaccount_instance(qaccount, instance)
    return GET_request("workloads/me", qaccount; instance, limit, backend)
end

function backend_status(backend_name::AbstractString, qaccount=nothing)
    return GET_request("backends/$backend_name/status", qaccount)
end

function backend_configuration(
    backend_name::AbstractString,
    qaccount=nothing;
    refresh::Opt{Bool}=nothing,
)
    _get_item =
        (backend_name, qaccount=nothing) ->
            GET_request("backends/$backend_name/configuration", qaccount)
    (_from_cache, response) =
        _cache_or_query(backend_name, "backend_configuration", _get_item, qaccount; refresh)
    return response
end

function backend_defaults(
    backend_name::AbstractString,
    qaccount=nothing;
    refresh::Opt{Bool}=nothing,
)
    _get_item =
        (backend_name, qaccount=nothing) ->
            GET_request("backends/$backend_name/defaults", qaccount)
    (_from_cache, response) =
        _cache_or_query(backend_name, "backend_defaults", _get_item, qaccount; refresh)
    return response
end

function backend_properties(
    backend_name::AbstractString,
    qaccount=nothing;
    updated_before=nothing,
    refresh::Opt{Bool}=nothing,
)
    _get_item =
        (backend_name, qaccount=nothing) ->
            GET_request("backends/$backend_name/properties", qaccount)
    # kws will fail if updated_before is supplied. We need to find how to pass them.
    kws = isnothing(updated_before) ? nothing : (:updated_before => updated_before)
    (_from_cache, response) = _cache_or_query(
        backend_name,
        "backend_properties",
        _get_item,
        qaccount;
        refresh,
        kws,
    )
    return response
end

function logs(job_id, qaccount=nothing; refresh::Opt{Bool}=nothing)
    _get_logs = (job_id, qaccount_=nothing) -> GET_request("jobs/$job_id/logs", qaccount_)
    (_from_cache, response) = _cache_or_query(job_id, "logs", _get_logs, qaccount; refresh)
    return response
end

function run_job(
    backend_name::AbstractString,
    pubs,
    qaccount=nothing;
    options=nothing,
    support_qiskit::Bool=true,
    tags=nothing,
    session_id=nothing,
    log_level=nothing,
)
    if !isnothing(session_id)
        session_id = string(session_id)
    end
    body = _run_job_dict(
        backend_name,
        pubs,
        qaccount;
        options,
        support_qiskit,
        tags,
        session_id,
        log_level,
    )
    body_json = JSON.write(body)
    return POST_request("jobs", body_json, qaccount)
end

function cancel_job(job_id, qaccount=nothing)
    return POST_request("jobs/$job_id/cancel", nothing, qaccount)
end

function delete_server_job(job_id, qaccount=nothing)
    return DELETE_request("jobs/$job_id", qaccount)
end

# Requests the minimum amount of data, just to see if the job exists.
function job_exists(job_id, qaccount=nothing)
    response = GET_request_inner("jobs/$job_id", qaccount; exclude_params=true)
    response.status == 200 && return true
    response.status == 404 && return false
    throw(RuntimeServiceException(response))
end

function get_tags(
    search::AbstractString,
    qaccount=nothing;
    limit::Opt{Integer}=nothing,
    offset::Opt{Integer}=nothing,
    refresh::Opt{Bool}=nothing,
)
    _get_item =
        (search, qaccount_=nothing; kws...) ->
            GET_request("facade/v1/jobs/tags", qaccount_; search=search, kws...)
    kws = (limit=limit, offset=offset)
    cache_name = string(search, "-", offset, "-", limit)
    (from_cache, response) = _cache_or_query(
        search,
        "tags",
        _get_item,
        qaccount;
        refresh,
        kws,
        cache_name=cache_name,
    )
    return response
    #    return GET_request("facade/v1/jobs/tags", qaccount; search=search, limit, offset)
end

function job_type(job_id, qaccount=nothing; refresh::Opt{Bool}=nothing)
    _get_item =
        (job_id, qaccount_=nothing) -> GET_request("facade/v1/jobs/$job_id/type", qaccount_)
    (_from_cache, response) = _cache_or_query(job_id, "type", _get_item, qaccount; refresh)
    return response
end

"""
    open_session(backend_name, qaccount=nothing; max_session_ttl::Opt{Integer}=400, mode)

"""
function open_session(
    backend_name,
    qaccount=nothing;
    mode,
    max_session_ttl::Opt{Integer}=nothing,
)
    mode = string(mode)
    qaccount = isnothing(qaccount) ? Accounts.QuantumAccount() : qaccount
    instance = string(qaccount.instance)
    body = Dict{Symbol,Any}(:backend => backend_name, :instance => instance, :mode => mode)
    isnothing(max_session_ttl) || (body[:max_session_ttl] = max_session_ttl)
    body_json = JSON.write(body)
    response = POST_request("sessions", body_json, qaccount)
    return response.id
end

function get_session(session_id, qaccount=nothing; refresh::Opt{Bool}=nothing)
    _get_item =
        (session_id, qaccount_=nothing) -> GET_request("sessions/$session_id", qaccount_)
    (from_cache, response) =
        _cache_or_query(session_id, "sessions", _get_item, qaccount; refresh)
    return (from_cache, response)
end

function get_session_jobs(session_id, qaccount=nothing; refresh::Opt{Bool}=nothing)
    _get_item =
        (session_id, qaccount_=nothing; kws...) ->
            GET_request("sessions/$session_id/jobs", qaccount_; kws...)
    kws = (limit=50,)
    (from_cache, response) =
        _cache_or_query(session_id, "sessions_jobs", _get_item, qaccount; refresh, kws)
    return (from_cache, response)
end

function close_session(session_id, qaccount=nothing)
    # This DELETE endpoint is supposed to "close" the session.
    # It actually stops jobs from running.
    # DELETE_request("sessions/$session_id/close", qaccount)
    # This endpoint is what the python client uses.
    return PATCH_request(
        "sessions/$session_id",
        qaccount;
        body=Dict(:accepting_jobs => false),
    )
end

# This is a different endpoint than the one hit by get_tags
function get_tags2(search_string, qaccount=nothing; refresh::Opt{Bool}=nothing)
    return GET_request("tags", qaccount; type="job", search=search_string)
    # _get_item =
    #     (_dummy, qaccount_=nothing) -> GET_request("tags", qaccount_)
    # (_from_cache, response) =
    #     _cache_or_query("alltags", "tags", _get_item, qaccount; refresh)
    # # Return just the response. We could make some effort to see if more tags
    # # have been added (or removed?). In that case, we'd want to return `from_cache`
    # # as well.
    # return response
end

end # module Requests
