# Tutorial

This is not a really tutorial. It's a demonstration of a few things that you can try

!!! note
    This tutorial assumes you have valid account info in `~/.qiskit/qiskit-ibm.json`.

!!! note
    I would be surprised if this works for you on the first attempt. This was all developed in
    a particular environment, with a particular subset of the data returned by the REST API.

Pull in a lot of symbols.
```julia-repl
julia> using QiskitRuntime
```
You can also get exported symbols from only one module, e.g. `using QiskitRuntime.Jobs`.

Retrieve job ids from the server. Note that an iterator is returned. So we use `collect`.
```julia-repl
julia> ajob_ids = collect(job_ids());

julia> print(ajob_ids[1:5])
JobId[JobId("cxp4fhy0v15000804nsg"), JobId("cxp4fhpwk6yg008hjy5g"), JobId("cxd6a7rbqkhg008kef50"), JobId("cxd6a70pjw30008g32y0"), JobId("cxd6a60px23g008t7nz0")]
```

Fetch the "jobs", that is input information and results, for each job id. Note that we choose to throw the
returned objects away. But they are cached in `~/.qiskit/runtime_cache`.
```julia-repl
julia> foreach(jid -> job(jid; refresh=true), ajob_ids)
```
We used `refresh=true` to make sure we fetch data from the server, not from the cache.

You can get the (freshly) cached job ids like this:
```julia-repl
julia> jids = collect(cached_job_ids()); length(jids)
39

julia> jid = jids[end]
JobId("wlv2rkrosk0uef9vfhpy")
```

Now fetching the GET response from the cache, and decoding it (including native Julia types) is fast, even though it is not
optimized at all.
```julia-repl
julia> @btime job($jid);
  414.767 μs (12001 allocations: 564.11 KiB)
```

In general, `job(jid)` will build a big nested object. So I don't print one of them here.
However, you can request that the `results` and job parameters `params` (including the input PUBs)
be omitted.
```julia-repl
julia> job(jid; results=false, params=false)
RuntimeJob{Nothing, Nothing}(
  job_id = JobId("wlv2rkrosk0uef9vfhpy"),
  user_id = QiskitRuntime.Accounts.UserId("XXXXXXXXXXXXXXXXXXXXXXXX"),
  session_id = JobId("wlv2rkrosk0uef9vfhpy"),
  primitive_id = Estimator::PrimitiveType = 0,
  backend_name = "ibm_brisbane",
  creation_date = 2024-12-25T17:58:31.640,
  end_date = 2024-12-25T18:12:12.882,
  instance = Instance(my-hub/my-group/my-project),
  status = Done::JobStatus = 2,
  cost = 18000,
  private = false,
  tags = ["everything", "PEC", "Container Tests"],
  params = nothing,
  results = nothing
)
```
