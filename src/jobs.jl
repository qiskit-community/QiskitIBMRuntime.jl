# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

module Jobs

using ArguMend: @argumend
using StructEquality: @struct_hash_equal
using Dates: DateTime, Dates
import Base: Generator
import ..Instances: Instance
import ..Utils: Utils, @pretty_show, Iter
using ..Decode: Decode, parse_datetime, try_parse_datetime
import ..PrimitiveResults
import ..Ids: JobId, UserId, SessionId, JobIdOrString, SessionIdOrString
import ..PUBs: PrimitiveType, EstimatorType, SamplerType
using ..Types: Opt, StringOrSymbol
using ..EnvVars: EnvVars
using ..Requests: JobResponse, MetricsResponse
import ..Requests: in_final_state
using ..Parameters2: @with_kw
using ..ConvertCase
using ..Options: EstimatorOptions, SamplerOptions

using SumTypes: @sum_type, @cases

"""
    JobStatus

Status of a job as reported by a query to the Runtime.
* `Queued`
* `Running`
* `Done`
* `Error`
* `Cancelled`
"""
@sum_type JobStatus begin
    Queued
    Running
    Done
    Error
    Cancelled
end

# INITIALIZING = "job is being initialized"
# QUEUED = "job is queued"
# VALIDATING = "job is being validated"
# RUNNING = "job is actively running"
# CANCELLED = "job has been cancelled"
# DONE = "job has successfully run"
# ERROR = "job incurred error"

"job is queued"
Queued

"job is actively running"
Running

"job has successfully run"
Done

"job has been cancelled"
Cancelled

"job incurred error"
Error

# Using `==` instead of `===` is 5x slower:
# return s === Done || s === Failed
# Using @cases is fast as ===
function in_final_state(s::JobStatus)
    @cases s begin
        Done => true
        Error => true
        Cancelled => true
        _ => false
    end
end

function Base.convert(::Type{JobStatus}, status::StringOrSymbol)
    status = Symbol(status)
    status === :Queued && return Queued
    status === :Running && return Running
    status === :Completed && return Done
    status === :Failed && return Error
    status === :Cancelled && return Cancelled
end

# We need to do something better with options and pubs
@struct_hash_equal struct JobParams{PT}
    support_qiskit::Opt{Bool}
    version::VersionNumber
    resilience_level::Opt{Int} # I think this is deprecated
    options::Opt{Union{EstimatorOptions,SamplerOptions}}
    #    options::Opt{Dict{Symbol,Any}}
    pubs::Vector{PT}
end

@pretty_show(JobParams)

"""
    struct Metrics

Contains data on running a particular job.

This includes timing, usage, number of qubits used, etc.
Data and metadata describing the job itself are in `RuntimeJob`.

See [`metrics`](@ref), [`job`](@ref).
"""
struct Metrics
    timestamps::Dict{Symbol,Opt{DateTime}}
    estimated_start_time::Opt{DateTime}
    estimated_completion_time::Opt{DateTime}
    circuit_depths::Opt{Vector{Int}}
    num_qubits::Opt{Vector{Int}}
    usage_seconds::Opt{Int}
    usage_quantum_seconds::Int
    num_circuits::Opt{Int}
    executions::Opt{Int}
    position_in_queue::Any # FIXME
    position_in_provider::Any # FIXME
end

@pretty_show(Metrics)

"""
    in_final_state(m::Metrics)

Return `true` if `m` is in a final state.

This is determined by a timestamap `:finished`, which may be
present or absent.
"""
function in_final_state(m::Metrics)
    return haskey(m.timestamps, :finished)
end

"""
    metrics(job_id::JobIdOrString, account=nothing; refresh::Bool=false)::Metrics

Return the metrics for job `job_id`.

By default, these metrics are also included as a field in the `RuntimeJob` returned by `job`.

See [`job`](@ref), [`results`](@ref).
"""
@argumend function metrics(
    job_id::JobIdOrString,
    account=nothing;
    refresh::Opt{Bool}=nothing,
)
    job_id = JobId(job_id)
    (_from_cache, res) = Requests.metrics(job_id, account; refresh)
    res = res.response
    st = try_parse_datetime(res.timestamps.created)
    finished = get(res.timestamps, :finished, nothing)
    running = get(res.timestamps, :running, nothing)
    fi = try_parse_datetime(finished)
    runi = try_parse_datetime(running)
    est = try_parse_datetime(res.estimated_start_time)
    efi = try_parse_datetime(res.estimated_completion_time)
    timestamps = Dict(:created => st, :finished => fi, :running => runi)
    decode = Decode.decode

    return Metrics(
        timestamps,
        est,
        efi,
        decode(res.circuit_depths),
        res.num_qubits,
        res.usage.seconds,
        res.usage.quantum_seconds,
        res.num_circuits,
        res.executions,
        res.position_in_queue,
        res.position_in_provider,
    )
end

# TODO: Parameterize or no ?
@struct_hash_equal struct RuntimeJob # {ResultT,ParamsT<:Opt{JobParams}}
    job_id::JobId
    user_id::UserId
    session_id::Opt{SessionId}
    primitive_id::PrimitiveType
    backend_name::String
    creation_date::DateTime
    end_date::Opt{DateTime}
    instance::Instance
    # state and status in Python runtime and REST API is quite complicated
    # We simply copy the REST API strings here. But this should be revisted.
    state::Dict{Symbol,Any}
    status::JobStatus
    cost::Int
    private::Bool
    tags::Vector{String}
    params # ::ParamsT
    results # ::ResultT
    metrics::Opt{Metrics}
end

@pretty_show(RuntimeJob)

function Base.isless(j1::RuntimeJob, j2::RuntimeJob)
    return isless(j1.creation_date, j2.creation_date)
end

"""
    in_final_state(jb::RuntimeJob)

Return `true` if `jb` is in a final state.
"""
function in_final_state(jb::RuntimeJob)
    return in_final_state(jb.status)
end

"""
    in_final_state(job_id::JobIdOrString, account=nothing; refresh=nothing)

Return true if the job labeld by `job_id` is in a final state.
# Examples
```jldoctest
julia> all(in_final_state.(cached_job_ids(); refresh=false))
true
```
"""
@argumend function in_final_state(job_id::JobIdOrString, account=nothing; refresh=nothing)
    return in_final_state(
        job(JobId(job_id), account; results=false, params=false, metrics=false, refresh),
    )
end

@struct_hash_equal struct SamplerPUB{CT,PT}
    circuit::CT
    parameters::Vector{PT}
    shots::Int
end

@pretty_show(SamplerPUB)

@struct_hash_equal struct EstimatorPUB{CT,PT,OT}
    circuit::CT
    observables::OT # ::Vector{OT}
    parameters::PT  # ::Vector{PT}
    precision::Float64
end

@pretty_show(EstimatorPUB)

module _Jobs

using Dates: DateTime
import ...Utils
import ...Decode
using ...Decode: parse_datetime, try_parse_datetime
import ...Instances: Instance
import ...Requests
import ...PauliOperators: PauliOperator
import ...Ids: JobId, UserId, SessionId
import ...PUBs: PrimitiveType, SamplerType, EstimatorType
import ...Options: SamplerOptions, EstimatorOptions, Auto

import ..EstimatorPUB
import ..SamplerPUB

import ..JobStatus
import ..Queued
import ..Running
import ..Done
import ..Error
import ..Cancelled
import ..JobParams
import ..RuntimeJob

function _decode_pub_sampler(pub)
    npub = [
        begin
            p = isa(p, Dict{Symbol,<:Any}) ? Decode.decode(p) : p
        end for p in pub
    ]
    if length(npub) == 2
        return SamplerPUB(npub..., 0)
    end
    isnothing(npub[3]) && (npub[3] = 0)
    return SamplerPUB(npub...)
end

function _decode_pub_estimator(pub)
    decode = Decode.decode
    if length(pub) == 3
        (circuit, observables, parameters) = (pub...,)
        precision = nothing
    else
        (circuit, observables, parameters, precision) = (pub...,)
    end
    isnothing(precision) && (precision = 0.0)
    observables = _decode_observables(observables)
    # if isa(observables, Dict{Symbol,<:Any})
    #     observables = Dict(PauliOperator(String(k)) => v for (k, v) in observables)
    # else
    #     observables = [PauliOperator(op) for op in observables]
    #     #        observables = decode(observables)
    # end
    return EstimatorPUB(decode(circuit), observables, decode(parameters), precision)
end

_decode_observables(observable::AbstractString) = PauliOperator(observable)
_decode_observables(observables::AbstractVector) = map(_decode_observables, observables)
_decode_observables(obs::Dict) = Dict(PauliOperator(String(k)) => v for (k, v) in obs)

function _decode_pubs(primitive_id, pubs)
    if primitive_id === EstimatorType
        [_decode_pub_estimator(pub) for pub in pubs]
    elseif primitive_id === SamplerType
        [_decode_pub_sampler(pub) for pub in pubs]
    else
        throw(ErrorException("Unexpected error")) # should be an assertion or s.t.
    end
end

encode_options(dict) = encode_options!(copy(dict))

# Get a strategy and put this elsewhere.
function encode_options!(dict)
    for (k, v) in dict
        if v == "auto"
            dict[k] = Auto()
        elseif isa(v, Dict)
            dict[k] = encode_options!(v)
        end
    end
    return dict
end

# Decode the "params" field/key for job info
# `primitive_id` - the primitive type; estimator or sampler
# `dict` - the field `params` from job info from server, as a JSON3 object.
function _job_params(primitive_id::PrimitiveType, dict)
    pubs = _decode_pubs(primitive_id, dict[:pubs])
    options = get(dict, :options, nothing)
    if isnothing(options) || isempty(options)
        options = nothing
    end
    if !isnothing(options)
        # The following removes the field `enable`.
        # dd = get(options, :dynamical_decoupling, nothing)
        # if !isnothing(dd)
        #     henable = get(dd, :enable, nothing)
        #     if henable === false
        #         delete!(options, :dynamical_decoupling)
        #     elseif !isnothing(henable)
        #         delete!(dd, :enable)
        #     end
        # end
        encode_options!(options)
        #        options = encode_options(options)
        if primitive_id === EstimatorType
            options = EstimatorOptions(; options...)
        elseif primitive_id === SamplerType
            options = SamplerOptions(; options...)
        else
            throw(ErrorException("Unexpected error")) # should be an assertion or s.t.
        end
    end
    return JobParams(
        get(dict, :support_qiskit, nothing),
        VersionNumber(dict[:version]),
        get(dict, :resilience_level, nothing),
        options,
        pubs,
    )
end

function _make_job(response, results=nothing, metrics_=nothing; params::Bool=true)
    instance = Instance(response.hub, response.group, response.project)

    session_id = let session_id = response.session_id
        isnothing(session_id) ? nothing : SessionId(session_id)
    end
    tags = let tags = response.tags
        isnothing(tags) ? String[] : collect(tags)
    end
    primitive_id = convert(PrimitiveType, response.program.id)

    # `copy` converts JSON3 efficienct structure into plain old types.
    # This is a bit wasteful. We should pass JSON3 first
    if params && !isnothing(get(response, :params, nothing))
        job_params = _job_params(primitive_id, copy(response.params))
    else
        job_params = nothing
    end

    # TODO: use @with_kw
    return RuntimeJob(
        JobId(response.id), # job_id
        UserId(response.user_id), # user_id
        session_id, # session_id
        primitive_id,
        response.backend, # backend_name
        parse_datetime(response.created), # creation_date
        try_parse_datetime(response.ended), # end date
        instance, # instance
        Decode.decode(response.state),
        convert(JobStatus, response.status), # status
        response.cost, # cost
        response.private, # private
        tags, # tags
        job_params,
        results,
        metrics_,
    )
end

end # module _Jobs

import ..Requests: Requests
import ..Accounts
import ..Instances: Instance
import ..PUBs: AbstractPUB

# Only here to allow non-fully-qualified symbols in docstring links.
# There should be a better way to do this.
import ..Backends
import ..PUBs

import ._Jobs: _make_job

export intag,
    anyintag,
    allintag,
    Batch,
    BatchInfo,
    InstancePlan,
    JobId,
    JobParams,
    JobStatus,
    Metrics,
    PrimitiveType,
    RuntimeJob,
    SessionMode,
    SessionState,
    UserInfo,
    cached_job_ids,
    cached_jobs,
    cancel_job,
    cached_session_ids,
    close_session,
    delete_cached_job,
    delete_job,
    delete_server_job,
    get_job_id,
    get_params,
    get_pubs,
    get_result_data,
    get_status,
    get_tags,
    get_usage,
    get_options,
    job,
    job_exists,
    job_ids,
    job_info,
    jobs,
    in_final_state,
    list_cached_tags,
    list_tags,
    metrics,
    open_session,
    results,
    run_job,
    session_info,
    session_job_ids,
    user_info

"""
    job(job_id::JobIdOrString, account=nothing; params::Bool=true, results::Bool=true, metrics::Bool=true, refresh::Opt{Bool}=nothing)::RuntimeJob

Return information on `job_id`.

- `params`: If `true` include job input parameters (including the [PUBs](https://docs.quantum.ibm.com/guides/primitive-input-output))).
            Otherwise the field `params` has value `nothing`.
- `metrics`: If `true` include metrics
- `results`: If `true` and the job has not failed, attempt to get the job results via the function [`results`](@ref).
             Otherwise, the field `results` has value `nothing`.
- `refresh`: If `nothing` and job data is cached, data for the fields will be refreshed from the server only if the status
             is "Running" or "Queued". If `true`, unconditionally refresh the cache for job data.
             If `false`, unconditionally prefer the cache. Separate caches are maintained for job info, metrics,
             and results. If any of the keyword arguments `params`, `metrics` or `results` is `false`, then data
             for that field will not be fetched; neither from the cache nor server.

See [`results`](@ref), [`metrics`](@ref).
"""
function job(
    job_id::JobIdOrString,
    account=nothing;
    params::Bool=true,
    results::Bool=true,
    metrics::Bool=true,
    refresh::Opt{Bool}=nothing,
)
    job_id = JobId(job_id)
    from_cache::Bool = false # value is arbitrary. we just need to define it.
    exclude_params::Bool = !params
    (from_cache, job_response) = Requests.job(job_id, account; exclude_params, refresh)
    # If info did come from cache and status was not final, then refresh with API request. (unless refresh==false)
    if from_cache && (refresh != false) && !in_final_state(job_response)
        (_unused_from_cache, job_response) =
            Requests.job(job_id, account; exclude_params, refresh=true)
    end
    status = Requests.get_status(job_response)
    if status != "Completed"
        # If status is "Failed" and we try to read results from the server, we won't
        # get results. In fact not even a json object. We just get a string containing an
        # error message. In Requests.GET_request, we choose to throw an error in this
        # case.
        # So if status is "Failed", we don't send a request to avoid throwing an error.
        # If status is"Running", "Queued", then it's ok to query for results, but we will get nothing.
        # So, we only query for results when status is "Completed"
        the_results = nothing
    else
        the_results = results ? Jobs.results(job_id, account; refresh) : nothing
    end
    if status === "Failed"
        # There *are* metrics for a failed job, but they are not interesting.
        the_metrics = nothing
    else
        if metrics
            (from_cache, metrics_response) =
                Requests.metrics(job_id, account; refresh=refresh)
            # If from cache, and not final, and refresh != false, then fetch metrics from server
            if from_cache && !in_final_state(metrics_response) && refresh != false
                the_metrics = Jobs.metrics(job_id, account; refresh=true)
            else
                # This certainly will get cached metrics if we get this far.
                the_metrics = Jobs.metrics(job_id, account; refresh=false)
            end
        else
            the_metrics = nothing
        end
    end
    return _make_job(job_response.response, the_results, the_metrics; params)
end

# Certainly want to wrap the job_id. If not, server will return false
# even when the problem is a malformed id.
"""
    job_info(job_id::JobIdOrString; refresh=false)

Return abbreviated job information with no input parameters and no results.
"""
function job_info(job_id::JobIdOrString, account=nothing; refresh::Opt{Bool}=nothing)
    return job(JobId(job_id), account; refresh, results=false, params=false, metrics=false)
end

"""
    job_exists(job_id::JobIdOrString, account=nothing)

Return `true` only if `job_id` exists on the server.

The job data may exist in local cache even if it was deleted from the server.
"""
function job_exists(job_id::JobIdOrString, account=nothing)
    return Requests.job_exists(JobId(job_id), account)
end

"""
    job(job_in::RuntimeJob, account=nothing;  params::Bool=true, results::Bool=true, refresh::Opt{Bool}=nothing)::RuntimeJob

Return information on `job_in`.

The fields `job_in.params` and `job_in.results` may have value `nothing`. Use this method to return a copy of `job_in` with
one or both of these fields populated, according to the keyword arguments `params` and `results`. These keyword arguments
are described in [`job`](@ref)(::JobIdOrString).

!!! note
    This function would be more useful if it were optimized to fetch only the needed additional data, copying the rest from
    `jobin`. In fact, at present, it constructs the entire `RuntimeJob` from scratch.
"""
@argumend function job(
    _job::RuntimeJob,
    account=nothing;
    params::Bool=true,
    results::Bool=true,
    metrics::Bool=true,
    refresh::Bool=false,
)
    return job(_job.job_id, account; params, results, metrics, refresh)
end

"""
    job_ids(account=nothing)

Return an iterator over `JobId`s for all jobs.

`job_ids` first requests information on the jobs from the server, then extracts the ids. This function
always makes requests to the REST API and does not access the cache.

# Keyword arguments

- `tags`:  A list of tags to filter jobs. (The search must match *all* tags?)
- `limit::Opt{Ingeter}`: Number of results to return at a time.
- `offset::Opt{Integer}`: Number of results to offset when retrieving the list of jobs.
- `pending::Opt{Bool}`: If true, return only jobs not in a final state. If `false`
   return only the complement.
- `instance::Opt{Union{AbstractString,Instance}}` instance to filter jobs. Either
   an `Instance` or a string in format `{hub}/{group}/{project}`.

Use [`cached_job_ids`](@ref) to get ids only for cached job requests.
"""
function job_ids(
    account=nothing;
    tags=nothing,
    limit::Opt{Integer}=nothing,
    offset::Opt{Integer}=nothing,
    exclude_params::Opt{Bool}=nothing,
    pending::Opt{Bool}=nothing,
    instance::Opt{Union{AbstractString,Instance}}=nothing,
)::Iter{JobId}
    # exclude params because we don't need them to get job ids.
    ids = Requests.job_ids(
        account;
        tags,
        limit,
        offset,
        pending,
        instance,
        exclude_params=true,
    )
    return Iter{JobId}(JobId(id) for id in ids)
end

"""
    jobs(job_ids, account=nothing; kwargs...)

Return an iterator over `RuntimeJob`s for each id in `job_ids`.

Keyword arguments are the same as for [`job`](@ref).
"""
function jobs(
    job_ids,
    account=nothing;
    params::Bool=true,
    results::Bool=true,
    metrics::Bool=true,
    refresh::Opt{Bool}=nothing,
)::Iter{RuntimeJob}
    gen = (job(job_id, account; params, results, metrics, refresh) for job_id in job_ids)
    return Iter{RuntimeJob}(gen)
end

function jobs(session_id::SessionId, qaccount=nothing; refresh::Opt{Bool}=nothing)
    job_ids = session_job_ids(session_id, qaccount; refresh)
    gen = (job(job_id) for job_id in job_ids)
    return Iter{RuntimeJob}(gen)
end

"""
    cached_job_ids(; filt=nothing)

Return an iterator over `JobId`s of cached jobs.

# Keyword arguments

- `filt` is either `nothing` or a function of one parameter. The argument for each cached id
   will be job info returned by `Requests.job`. This job info has been decoded by the
   default JSON3 decoder. It has not been further decoded into higher level `struct`s such
   as `RuntimeJob`. One reason is that a failed job may have unpredictable data
   (i.e. erroneous primtive options that are given to the server will be returned by the
   server). Examples of filter functions are given below.

Use [`job_ids`](@ref) to request ids from the REST API.

# Examples

Check that all cached jobs are in a final state.
```jldoctest
julia> all(id -> in_final_state(id; refresh=false), cached_job_ids())
true
```

Check that all cached jobs are in final state, while refreshing possibly stale
values of `false`.
```julia-repl
julia> all(in_final_state, cached_job_ids())
true
```
Note that the two examples above do not check that all results have been cached.


Count cached job ids.
```jldoctest
julia> length(cached_job_ids())
2
```

Use filters.
```jldoctest
julia> [get_status(id; refresh=false) for id in cached_job_ids(; filt = jb -> jb.status == "Failed")]
1-element Vector{JobStatus}:
 Error::JobStatus

julia> cached_job_ids(; filt = jb -> jb.program.id == "sampler");

julia> cached_job_ids(; filt = jb -> intag("atag", jb));
```
"""
function cached_job_ids end

let
    global cached_job_ids
    function cached_job_ids(; filt=nothing)
        ids = Requests.cached_job_ids()
        if isnothing(filt)
            return Iter{JobId}(Base.Generator(JobId, ids))
        end
        return _cached_job_ids_filter(ids, filt)
    end

    function _cached_job_ids_filter(ids, filtfunc::F) where {F}
        fn = id -> Requests.job(id; refresh=false)[2].response
        f_ids = Iterators.filter(id -> filtfunc(fn(id)), ids)
        return Iter{JobId}(Base.Generator(JobId, f_ids))
    end
end # let

"""
    cached_session_ids()

Return a sorted, unique, list of session ids retrieved from cached job ids.
"""
function cached_session_ids()
    return map(SessionId, Requests.cached_session_ids())
end

"""
    cached_jobs(account=nothing; params::Bool=true, results::Bool=true, metrics::Bool=true, refresh::Opt{Bool}=nothing, filt=nothing)

Return an iterator over all cached jobs, where items are `RuntimeJob`s.

See [`job`](@ref) for information on the keyword arguments.

!!! note
    Although the job ids and info are retrieved from cache, further data may be fetched from cache
    or the server if indicated by the keyword arguments, job status, and cache status.
"""
function cached_jobs(
    account=nothing;
    params::Bool=true,
    results::Bool=true,
    metrics::Bool=true,
    refresh::Opt{Bool}=nothing,
    filt=nothing,
)
    if isnothing(filt)
        return (
            job(id, account; params, results, metrics, refresh) for
            id in Requests.cached_job_ids()
        )
    end
    return Iter{RuntimeJob}(
        job(id, account; params, results, metrics, refresh) for id in cached_job_ids(; filt)
    )
end

@struct_hash_equal struct InstancePlan
    instance::Instance
    plan::String
end

@pretty_show(InstancePlan)

@struct_hash_equal struct UserInfo
    email::String
    instances::Vector{InstancePlan}
end

@pretty_show(UserInfo)

"""
    user_info(account=nothing; refresh=false)::UserInfo

Return information about the user.

Information includes the user's email and a list of available instances.

!!! note
    The user info returned by the server is determined by the authentication token.
    Unlike other cached information, we do not key the cache by this information in order
    to avoid writing the token as plain text. So if you have more than one account, each
    with an associated token, the cache will not distinguish them. If you switch accounts
    and tokens, you should pass `refresh=true`.

    If you merely generate and use a new token for a single account, you do not need to
    refresh the cache.
"""
function user_info(account=nothing; refresh=false)
    _user = Requests.user_info(account; refresh)
    instances = [InstancePlan(Instance(inst.name), inst.plan) for inst in _user.instances]
    return UserInfo(_user.email, instances)
end

# Sometimes "result" sometimes "results" in Python version. We should pick the right name.
"""
    results(job_id, account=nothing; refresh::Opt{Bool}=nothing)

Return results for `job_id`.

If no results are available, then `nothing` is returned.
See [`job`](@ref), [`metrics`](@ref).
"""
function results(job_id, account=nothing; refresh::Opt{Bool}=nothing)
    results_response = Requests.results(job_id, account; refresh)
    res = Decode.decode(results_response; job_id)

    # FIXME: Integrate this decoding into the `decode` methods.
    # If res is a Dict, we only recognize length of 2.
    if isa(res, Dict)
        length(res) == 2 &&
            return PrimitiveResults.PlainResult(res[:results], res[:metadata], job_id)
        # We don't know the structure of the `Dict`, so we just add the job id.
        res[:job_id] = job_id
    end

    return res
end

"""
    results(job::RuntimeJob, account=nothing; refresh=false)

Return results associated with `job`.

Results already contained in `job` are returned if it makes sense to do so.

More precisely, if `job.results` is not `nothing` and `refresh` is `false`, then `job.results` is
returned. If `job.results` is `nothing` then results are fetched from the cache or the REST API. If
`refresh` is `false` then the cache is preferred.
"""
function results(job::RuntimeJob, account=nothing; refresh::Opt{Bool}=nothing)
    (isnothing(job) || refresh) && return results(job.job_id, account; refresh)
    return job.results
end

"""
    struct Batch

Holds information identifying a session and the jobs
run in the session.

- `session_id::SessionId`: The session id.
- `job_ids::Vector{JobId}`: All job ids associated with this session.
"""
@struct_hash_equal struct Batch
    session_id::SessionId
    job_ids::Vector{JobId}

    function Batch(session_id::SessionId)
        return new(session_id, JobId[])
    end
end

@pretty_show Batch

"""
    jobs(batch::Batch, account=nothing; kwargs...)

Return an iterator over `RuntimeJob`s in `batch`.
"""
function jobs(
    batch::Batch,
    account=nothing;
    params::Bool=true,
    results::Bool=true,
    metrics::Bool=true,
    refresh::Opt{Bool}=nothing,
)
    return jobs(batch.job_ids, account; params, results, metrics, refresh)
end

@struct_hash_equal struct SessionMode
    mode::Symbol
    function SessionMode(mode_::StringOrSymbol)
        mode = Symbol(ConvertCase.snake_to_camel(string(mode_)))
        mode === :Batch ||
            mode === :Dedicated ||
            throw(ArgumentError(lazy"Unrecognized session mode \"$mode\""))
        return new(mode)
    end
end
function Base.string(mode::SessionMode)
    mode.mode === :Batch && return "batch"
    mode.mode === :Dedicated && return "dedicated"
end

@struct_hash_equal struct SessionState
    state::Symbol
    function SessionState(state_::StringOrSymbol)
        state = Symbol(ConvertCase.snake_to_camel(string(state_)))
        state === :Open ||
            state === :Closed ||
            throw(ArgumentError(lazy"Unrecognized session state \"$state\""))
        return new(state)
    end
end
Base.string(state::SessionState) = ConvertCase.camel_to_snake(string(state.state))

Base.convert(::Type{String}, mode::SessionMode) = string(mode)

"""
    open_session(backend_name::AbstractString, qaccount=nothing;  max_session_ttl::Opt{Integer}=nothing)

Open a session and return a `Batch` object.

This is called automatically by the `Batch` constructor.
"""
function open_session(
    backend_name::AbstractString,
    qaccount=nothing;
    max_session_ttl::Opt{Integer}=nothing,
    mode::Union{SessionMode,StringOrSymbol}=SessionMode(:Batch),
)
    isa(mode, SessionMode) || (mode = SessionMode(mode))
    return Requests.open_session(backend_name, qaccount; max_session_ttl, mode) |>
           SessionId |>
           Batch
end

"""
    close_session(batch::Batch, qaccount=nothing)

Close the session associated with `batch`.

This function is called automatically when calling the `Batch` constructor.
Note this doesn't really hit the "close" endpoint, but rather changes the state
of "accepting jobs" to `false`.
"""
function close_session(batch::Batch, qaccount=nothing)
    return Requests.close_session(batch.session_id.id, qaccount)
end

function get_session(batch::Batch, qaccount=nothing)
    return Requests.get_session(batch.session_id.id, qaccount)
end

"""
    Batch(func, backend_name::AbstractString, qaccount=nothing; max_session_ttl::Opt{Integer}=nothing,
           mode::Union{SessionMode,StringOrSymbol}=SessionMode(:Batch),

Open a session and call `func` on new `Batch` object.

The session is "closed" on exiting `func`. This is meant to be used with `do` block syntax.
"""
function Batch(
    func,
    backend_name::AbstractString,
    qaccount=nothing;
    max_session_ttl::Opt{Integer}=nothing,
    mode::Union{SessionMode,StringOrSymbol}=SessionMode(:Batch),
)
    batch = open_session(backend_name, qaccount; max_session_ttl, mode)
    try
        func(batch)
    finally
        close_session(batch, qaccount)
    end
    return batch
end

"""
    struct BatchInfo

Holds data describing session.

Either batch or dedicated session. This is returned
by `session_info`.

See [`session_info`](@ref).
"""
@with_kw struct BatchInfo
    id::SessionId
    backend_name::String
    mode::SessionMode
    interactive_ttl::Int
    max_ttl::Int
    active_ttl::Int
    accepting_jobs::Bool
    created_at::Dates.DateTime
    closed_at::Opt{Dates.DateTime}
    state::SessionState
    elapsed_time::Opt{Int}
end

# @struct_hash_equal BatchInfo # === is enough, I think. Not mutable
@pretty_show(BatchInfo)

function BatchInfo(d)
    closed_at = get(d, :closed_at, nothing)
    closed_at = isnothing(closed_at) ? nothing : parse_datetime(closed_at)
    return BatchInfo(;
        id=SessionId(d.id),
        backend_name=d.backend_name,
        mode=SessionMode(d.mode),
        interactive_ttl=d.interactive_ttl,
        max_ttl=d.max_ttl,
        active_ttl=d.active_ttl,
        accepting_jobs=d.accepting_jobs,
        created_at=parse_datetime(d.created_at),
        closed_at=closed_at,
        state=SessionState(d.state),
        elapsed_time=d.elapsed_time,
    )
end

function Base.isless(b1::BatchInfo, b2::BatchInfo)
    return isless(b1.created_at, b2.created_at)
end

session_info(batch::Batch, qaccount=nothing) = session_info(batch.session_id, qaccount)

"""
    session_info(session_id::SessionIdOrString, qaccount=nothing; refresh::Opt{Bool}=nothing)
    session_info(batch::Batch, qaccount=nothing)

Return a `BatchInfo` object with information on session, either batch or dedicated.

See [`BatchInfo`](@ref).
"""
function session_info(
    session_id::SessionIdOrString,
    qaccount=nothing;
    refresh::Opt{Bool}=nothing,
)
    session_id = SessionId(session_id)
    (from_cache, response) = Requests.get_session(session_id, qaccount; refresh)
    # If refresh is not specified and session is not finished, get update from server.
    if from_cache && isnothing(refresh) && !haskey(response, :closed_at)
        (from_cache_, response) = Requests.get_session(session_id, qaccount; refresh=true)
    end
    return BatchInfo(response)
end

# Returns only the first 50
function session_job_ids(
    session_id::SessionIdOrString,
    qaccount=nothing;
    refresh::Opt{Bool}=nothing,
)
    session_id = SessionId(session_id)
    (from_cache, response) = Requests.get_session_jobs(session_id, qaccount; refresh)
    # If refresh is not specified and session is not finished, get update from server.
    if from_cache && isnothing(refresh)
        for j in response.jobs
            if in(j.status, ("Queued", "Running"))
                (from_cache_, response) =
                    Requests.get_session_jobs(session_id, qaccount; refresh=true)
                break
            end
        end
    end
    return [JobId(j.id) for j in response.jobs]
end

# We can do this. But need to be careful about the differences in schema from
# requests.
# """
#     jobs(batch_info::BatchInfo, account=nothing; kwargs...)
# Return an iterator over `RuntimeJob`s for session id in `batch_info`.
# """
# function jobs(batch_info::BatchInfo,
#               account=nothing;
#               params::Bool=true,
#               results::Bool=true,
#               metrics::Bool=true,
#               refresh::Opt{Bool}=nothing)
#     return jobs(batch_info.id, account; params, results, metrics, refresh)
# end

"""
    run_job(backend_name::AbstractString, pubs::AbstractVector{<:AbstractPUB}, qaccount=nothing)
    run_job(backend_name::AbstractString, pub::AbstractPUB, qaccount=nothing)

Run `pubs` on device `backend_name`.

# Keyword arguments
- `options=nothing`: An instance of type `EstimatorOptions` or `SamplerOptions`.
- `support_qiskit=true`: If `true` results are returned in a more typed format with some
   data as serialized numpy arrays.
- `tags=nothing`: A list of `String`s.
- `log_level::Opt{String}=nothing`: Appears to do nothing.
- `batch::Opt{Batch}=nothing`: Add job to `Batch`.

See [`Accounts.QuantumAccount`](@ref), [`PUBs.EstimatorPUB`](@ref),
[`PUBs.SamplerPUB`](@ref), [`Backends.backends`](@ref).
"""
function run_job(
    backend_name::AbstractString,
    pubs::AbstractVector{<:AbstractPUB},
    qaccount=nothing;
    options::Union{EstimatorOptions,SamplerOptions,Nothing}=nothing,
    support_qiskit=true,
    tags=nothing,
    batch::Opt{Batch}=nothing,
    log_level::Opt{String}=nothing,
)
    if !(
        isnothing(log_level) ||
        log_level in ("critical", "error", "warning", "info", "debug")
    )
        throw(ArgumentError(lazy"Invalid log level \"$log_level\""))
    end

    session_id = isnothing(batch) ? nothing : batch.session_id

    response = Requests.run_job(
        backend_name,
        pubs,
        qaccount;
        options,
        support_qiskit,
        tags,
        session_id,
        log_level,
    )
    # This is awful type instability. Does it matter?
    !isnothing(EnvVars.get_env(:QISKIT_RUNTIME_DRY_RUN)) && return response
    job_id = JobId(response.id)
    if !isnothing(batch)
        push!(batch.job_ids, job_id)
    end
    return job_id
end

function run_job(backend_name, pub::AbstractPUB, args...; kwargs...)
    return run_job(backend_name, [pub], args...; kwargs...)
end

"""
    cancel_job(job_id::JobId, account=nothing)

Attempt to cancel job with id `job_id`.

Returns `nothing` on success.
"""
function cancel_job(job_id::JobId, account=nothing)
    return Requests.cancel_job(job_id, account)
end

cancel_job(job_id::AbstractString, account=nothing) = cancel_job(JobId(job_id), account)

"""
    delete_server_job(job::Union{JobId, RuntimeJob}, account=nothing)

Delete `job` from the server.

Returns `nothing` on success. The local cache is not affected.

See [`delete_cached_job`](@ref), [`delete_job`](@ref).
"""
function delete_server_job(job_id::JobIdOrString, account=nothing)
    return Requests.delete_server_job(JobId(job_id), account)
end

delete_server_job(job::RuntimeJob) = delete_server_job(job.job_id)

"""
    delete_cached_job(job::Union{JobId, RuntimeJob})

Delete local cache associated with with `job`.

Data on the server associated with `job` is not altered or deleted.

See [`delete_server_job`](@ref), [`delete_job`](@ref).
"""
function delete_cached_job(job_id::JobIdOrString)
    return Requests._Requests.delete_id_cache_files(JobId(job_id))
end

delete_cached_job(job::RuntimeJob) = delete_cached_job(job.job_id)

"""
    delete_job(job::Union{JobId, RuntimeJob})

Delete data associated with `job` from the server and from the local cache.

This runs [`delete_server_job`](@ref) and [`delete_cached_job`](@ref).
"""
function delete_job(job)
    delete_server_job(job)
    return delete_cached_job(job)
end

metrics(jb::RuntimeJob) = jb.metrics

"""
    get_params(id::JobIdOrString, account=nothing; refresh::Opt{Bool}=nothing)
    get_params(jb::RuntimeJob)

Get input parameters associated with job.

This contains options and PUBs.
"""
function get_params(id::JobIdOrString, account=nothing; refresh::Opt{Bool}=nothing)
    return get_params(job(id, account; results=false, metrics=false, refresh))
end

get_params(jb::RuntimeJob) = jb.params

get_pubs(jp::JobParams) = jp.pubs

function get_pubs(id::JobIdOrString, account=nothing; refresh::Opt{Bool}=nothing)
    return get_pubs(get_params(id, account; refresh))
end

"""
    get_pubs(id::JobIdOrString, account=nothing; refresh::Opt{Bool}=nothing)
    get_pubs(jb::RuntimeJob)
    get_pubs(jp::JobParams)

Return a list of PUBs associated with a job from the object or resource.
"""
function get_pubs(jb::RuntimeJob)
    p = get_params(jb)
    isnothing(p) && return p
    return get_pubs(p)
end

"""
    get_usage(m::Metrics)
    get_usage(jb::RuntimeJob)
    get_usage(job_id, account=nothing; refresh::Opt{Bool}=nothing)

Get QPU usage (`usage_quantum_seconds`).
"""
function get_usage end

function get_usage(m::Metrics)
    return m.usage_quantum_seconds
end

function get_usage(jid::JobIdOrString, account=nothing; refresh::Opt{Bool}=nothing)
    return get_usage(job(jid, account; results=false, refresh))
end

function get_usage(jb::RuntimeJob)
    m = metrics(jb)
    isnothing(m) && return m
    return get_usage(m)
end

function get_status(jb::RuntimeJob)
    return jb.status
end

"""
    get_status(jid::JobIdOrString, account=nothing; refresh::Opt{Bool}=nothing)
    get_status(jb::RuntimeJob)

Return the status of the job.
"""
function get_status(jid::JobIdOrString, account=nothing; refresh::Opt{Bool}=nothing)
    return get_status(job_info(jid, account; refresh))
end

function get_tags(jb::RuntimeJob, idx=nothing)
    isnothing(idx) && return jb.tags
    return jb.tags[idx]
end

"""
    get_tags(jid::JobIdOrString, idx=nothing; account=nothing, refresh::Opt{Bool}=nothing)
    get_tags(jb::RuntimeJob, idx=nothing)

Return the tags associated with the job.

- `idx`: If not `nothing`, return `getindex(thetags, idx)`.
"""
function get_tags(
    jid::JobIdOrString,
    idx=nothing;
    account=nothing,
    refresh::Opt{Bool}=nothing,
)
    return get_tags(job_info(jid, account; refresh), idx)
end

"""
    list_cached_tags(search_term::Union{AbstractString, Regex, Nothing}=nothing)

Return a list of job tags, sorted and unique, and optionally filtered, from the cache.

The tags are extracted from cached job info. If no `search_term` is supplied,
all tags are returned. `search_term` is passed to `occursin`.
"""
function list_cached_tags(search_term::Union{AbstractString,Regex,Nothing}=nothing)
    tags = sort!(reduce((x, y) -> unique!(vcat(x, y)), map(get_tags, cached_job_ids())))
    isnothing(search_term) && return tags
    return filter(x -> occursin(search_term, x), tags)
end

"""
    list_tags(search_term::AbstractString, account=nothing; refresh::Opt{Bool}=nothing, limit::Opt{Integer}=nothing, offset::Opt{Integer}=nothing)

Return a list of tags matching `search_term`.

`search_term` must not be empty. An underscore also matches a space. Search is case insensitive.
`list_tags` queries the server and caches results.
"""
function list_tags(
    search_term::AbstractString,
    account=nothing;
    refresh::Opt{Bool}=nothing,
    limit::Opt{Integer}=nothing,
    offset::Opt{Integer}=nothing,
)
    response = Requests.get_tags(search_term, account; limit, offset, refresh)
    return collect(response.tags)
end

get_result_data(::Nothing) = nothing

function get_result_data(jb::RuntimeJob)
    return get_result_data(jb.results)
end

"""
    get_result_data(jid::JobIdOrString, account=nothing; refresh::Opt{Bool}=nothing)
    get_result_data(results::PrimitiveResults.PrimitiveResult)
    get_result_data(jb::RuntimeJob)

Get a list of results data, typically a `NamedTuple` with fields `evs`, etc. The list
contains one entry for each input PUB.
"""
function get_result_data(results::PrimitiveResults.PrimitiveResult)
    return [pr.data.fields for pr in results.pub_results]
end

function get_result_data(jid::JobIdOrString, account=nothing; refresh::Opt{Bool}=nothing)
    return get_result_data(results(jid, account; refresh))
end

function get_options(jb::RuntimeJob)
    return get_options(jb.params)
end
function get_options(p::JobParams)
    return p.options
end

"""
    get_options(jid::JobIdOrString, account=nothing; refresh::Opt{Bool}=nothing)
    get_options(jb::RuntimeJob)
    get_options(p::JobParams)

Get `EstimatorOptions` or `SamplerOptions` associated with a job, or job params.
"""
function get_options(jid::JobIdOrString, account=nothing; refresh::Opt{Bool}=nothing)
    j = job(JobId(job_id), account; refresh, results=false, params=true, metrics=false)
    return j.params.options
end

"""
    get_job_id(job::RuntimeJob)
    get_job_id(res::PrimitiveResults.PrimitiveResult)

Return the job id from field in the object.
"""
get_job_id(job::RuntimeJob) = job.job_id
get_job_id(res::PrimitiveResults.PrimitiveResult) = res.job_id

# I have not used this form yet. Maybe we don't need it.
intag(needle::Function, haystacks) = any(needle, haystacks)

intag(needle::AbstractString, haystacks) = in(needle, haystacks)
intag(needle::Regex, haystacks) = any(h -> occursin(needle, h), haystacks)
anyintag(needles, haystacks) = any(n -> intag(n, haystacks), needles)
allintag(needles, haystacks) = all(n -> intag(n, haystacks), needles)

for T in (:AbstractString, :Regex, :Function)
    @eval intag(needle::$T, ::Nothing) = false
end

"""
    intag(needle, tags)
    intag(needle, job_id)
    intag(needle, job)
    allintags(needles, tags)
    anyintags(needles, tags)

Return true if `needle` matches a tag in the list `tags`, or
in the tags associated with `job_id` or `job`.

If `needle` is an `AbstractString`, then the match must be exact.
If `needle` is a `Regex`, then the `Regex` much match.

`allintags` returns `true` if all items in `needles` match one of the tags.
`anyintags` returns `true` if any item in `needles` matches one of the tags.

# Examples
```jldoctest
julia> intag("cat", ["cat"])
true

julia> intag("dog", ["cat"])
false

julia> intag("dog", ["cat", "dog"])
true

julia> intag("dog", ["cat", "doggy"])
false

julia> intag(r"dog", ["cat", "doggy"])
true

julia> allintag([r"dog", "moose"], ["cat", "doggy"])
false

julia> anyintag([r"dog", "moose"], ["cat", "doggy"])
true
```
"""
intag(needle::Function, jb::RuntimeJob) = intag(needle, jb.tags)
intag(needle::Regex, jb::RuntimeJob) = intag(needle, jb.tags)
intag(needle::AbstractString, jb::RuntimeJob) = intag(needle, jb.tags)

let
    function _intag(needle, job_id)
        job = Requests.job(job_id)[2].response
        isnothing(job.tags) && return false
        return intag(needle, job.tags)
    end

    global intag
    intag(needle::Function, job_id::JobId) = _intag(needle, job_id)
    intag(needle::Regex, job_id::JobId) = _intag(needle, job_id)
    intag(needle::AbstractString, job_id::JobId) = _intag(needle, job_id)
end # let

for func in (:anyintag, :allintag)
    @eval $func(arg1, jb::RuntimeJob) = $func(arg1, jb.tags)
    @eval $func(arg1, job_id::JobId) = $func(arg1, Requests.job(job_id)[2].response.tags)
end

end # module Jobs
