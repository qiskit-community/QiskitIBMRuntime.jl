# QiskitIBMRuntime

[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

A Julia-language client for the IBM Quantum Platform via the REST API.

This client supports retrieving job data and reading it into Julia-native objects.
Support for submitting jobs is minimal.

To use install `QiskitIBMRuntime` do the following from the Julia REPL

```
julia> using Pkg
julia> pkg"registry add https://github.com/qiskit-community/QuantumRegistry"
julia> Pkg.add("QiskitIBMRuntime")
julia> using QiskitIBMRuntime
```

This adds a registry to your Julia installation that allows Julia to find this package and
its dependencies that are not in the General Registry


Documentation is not deployed online. You can view it like this:

* Read [./docs/make.jl](./docs/make.jl)
* Run [./docs/runserver.sh](./docs/runserver.sh)

Extensions using Python-language Qiskit packages, such as [qiskit](https://github.com/Qiskit/qiskit),
are provided by [QiskitIBMRuntimeX.jl](https://github.ibm.com/ibm-q-research/QiskitIBMRuntimeX.jl)

## Example

```julia-repl
julia> job_id = JobId("cxd21y7px23g008t7g8g")
JobId("cxd21y7px23g008t7g8g")

julia> the_job = job(job_id)
RuntimeJob{PrimitiveResult{SamplerPUBResult}, JobParams{QiskitIBMRuntime.Jobs.SamplerPUB{CircuitString, Float64}}}(
  job_id = JobId("cxd21y7px23g008t7g8g"),
  user_id = UserId("62dec6f8fe7a5778e04ec678"),
  session_id = nothing,
  primitive_id = SamplerType::PrimitiveType,
  backend_name = "ibm_nazca",
  creation_date = 2024-12-11T23:32:08.879,
  end_date = 2024-12-12T07:06:53.615,
  instance = Instance(my-hub/my-group/my-project),
  state = Dict{Symbol, String} with 1 entry:
  :status => "Completed",
  status = Done::JobStatus,
  cost = 10000,
  private = false,
  tags = String[],
  params =   JobParams{QiskitIBMRuntime.Jobs.SamplerPUB{CircuitString, Float64}}(
    support_qiskit = true,
    version = v"2.0.0",
    resilience_level = nothing,
    options = Dict{Symbol, Any}(),
    pubs = QiskitIBMRuntime.Jobs.SamplerPUB{CircuitString, Float64}[QiskitIBMRuntime.Jobs.SamplerPUB{CircuitString, Float64}(CircuitString(eJzsXXd4VUXzvvRQpEmR ... yUs6SiyhLTmL+H6v+pBI=), Float64[], 0)]
  ),
  results = PrimitiveResult{SamplerPUBResult}(
  pub_results = SamplerPUBResult[SamplerPUBResult(DataBin{@NamedTuple{meas::QiskitIBMRuntime.BitArraysX._BitArraysX.BitArrayAlt{UInt8, 2}}}((meas = Bool[0 1 … 0 1; 0 1 … 1 1; … ; 0 0 … 0 0; 0 0 … 0 0],)), Dict{Symbol, Dict{Any, Any}}(:circuit_metadata => Dict()))],
  metadata = Metadata(
  fields = Dict{Symbol, Any} with 2 entries:
  :execution => Dict{Symbol, Dict{Symbol, Vector{ExecutionSpan{Dict{Int64, Vector{Any}}}}}}(:execution_spans=>Dict(:spans=>[ExecutionSpan{Dict{Int64, Vector{Any}}}(DateTime("2024-12-12T07:05:29.475"), DateTime("…
  :version   => v"2.0.0",
  version = v"2.0.0"
),
  job_id = JobId("cxd21y7px23g008t7g8g")
)
)

julia> the_job.results.pub_results[1].data.fields.meas
127×4096 QiskitIBMRuntime.BitArraysX._BitArraysX.BitArrayAlt{UInt8, 2}:
 0  1  0  1  1  1  0  1  1  0  0  0  1  0  1  …  0  1  1  1  0  0  0  1  1  1  1  0  0  1
 0  1  1  1  0  0  0  0  1  1  0  0  1  0  0     1  0  0  0  1  1  0  1  0  0  1  0  1  1
 0  1  1  1  0  0  1  1  0  1  0  1  1  0  0     1  1  1  0  1  0  1  1  0  1  0  0  1  1
 1  0  1  0  1  0  0  0  1  1  1  1  0  0  1     0  0  0  0  0  0  0  1  0  1  1  1  0  0
 0  0  0  0  0  0  1  1  1  1  0  0  0  1  0     0  0  1  0  0  0  0  1  0  0  0  0  0  0
 0  0  0  1  1  0  0  1  1  0  1  1  0  0  1  …  0  1  1  1  1  1  1  0  0  1  0  1  1  1
 0  1  0  0  0  1  1  1  0  0  0  1  0  1  0     0  1  1  0  1  0  1  0  0  1  0  1  1  0
 0  0  1  1  0  0  1  0  0  0  1  1  1  1  0     1  1  0  0  0  1  0  0  1  1  0  0  1  1
 ⋮              ⋮              ⋮              ⋱           ⋮              ⋮              ⋮
 0  0  0  0  0  0  1  0  0  0  0  0  0  0  0  …  0  0  0  0  0  0  0  1  1  0  0  0  0  0
 0  1  1  1  1  1  1  1  1  0  0  0  1  0  1     0  0  1  0  0  1  0  0  1  0  0  0  0  0
 0  0  0  0  0  0  0  0  0  0  0  0  0  0  0     0  0  0  0  0  0  0  0  0  0  0  0  0  0
 0  0  0  0  0  0  0  0  0  0  0  0  0  0  0     0  0  0  0  0  0  0  0  0  0  0  0  0  0
 0  0  0  0  0  0  0  0  0  0  0  0  0  0  1     0  0  0  0  1  1  1  1  0  0  0  0  0  0
 0  0  0  0  1  0  0  0  1  0  0  0  0  0  0  …  0  0  0  0  0  0  0  1  0  0  0  0  0  0
 0  0  0  0  0  1  0  0  0  0  0  0  0  0  0     0  0  0  0  0  0  0  0  0  0  1  0  0  0
```
