# Development notes

```@contents
Pages = ["dev_notes.md"]
Depth = 3
```

## Consistency

A foolish inconsistency is the hobgoblin of little minds, adored by little lazy coders.

### Rules specific to this package

* Always "PUB" in types, function names, docs, comments. Never "Pub", "pub", etc.
  "pubs" is ok as a function parameter name. For example: `process_data(pubs)`.
* Always "credentials" file. Never "config" or anything else.
* Always "user qiskit directory". Never "config".
* The two previous items and similar apply in comments, doc strings, and function names.

### General rules

Better to go to one of the big projects and look at their rules. Maybe just adopt one of them.

* Underscores between words. I have a hard time remembering and applying this. It is also invites
  discussion. It also goes against long-standing Julia advice (which has also been disagreed with forever)

## Native Julia types

The REST API is Python-centric in a few ways. Numerical data is typically numpy data that
is serialized, compressed, and encoded.

We currently support much of this with conversion to native-Julia types
* numpy arrays are converted to `Array`
* Pauli strings represented as un-processed strings by the REST API, eg. "IXYZ" are converted to `PauliOperator` (see below).
* Bit-register samples (shots) are designed for compatibility with Qiskit's [BitArray](https://github.com/Qiskit/qiskit/blob/main/qiskit/primitives/containers/bit_array.py) (or the other way around). We have a custom type with the same semantics and memory layout (more or less)
  in src/bitarraysx.jl. This has some associated functionality, but it is limited compared to, say, `Base.BitArray`.
  At present, a fallback conversion via `BitArray(our_custom_array)` works, and is not terribly inefficient if you don't do it much.
  We may want take a different approach. Eg, go directly to `BitArray`, or...
* `QuantumCircuit`. We leave this in the same form we get it from the REST API. A string of the serialized-compressed-encoded data.
* QASM3 programs. These are handled by the REST API as plain strings with no encoding. (maybe QASM3 allows utf-8, which receives standard
  encoding, IDK). We do nothing with this at the moment other than store it.

## Python interop

You frequently need to refer to Python types in Julia docstrings.
We need a documentation convention to distinguish Python types from Jula types.

## Precompile

* precompile.jl script works by processing cached jobs in your `~/.qiskit` directory. (We cache
  REST responses there, the Python client does not) If you have no cached jobs, then precompilation
  should still succeed, but it will not be of any benefit.


  This is not a good general solution. If someone installs the package, they will have no cached jobs,
  and so get no benefit.

## Name spaces

Using modules to understand dependencies, and everything else good that they bring.
I also want to keep symbols intended to be private out of the REPL TAB completion, and other prying tools. There are
various methods in Julia-world to try to do this. I am sort of experimenting in an adhoc way

## Data structures

### Dicts

Discourage free-form dicts with string keys. Constrain values of inputs by construction.
Eg. in Python, `"measure_noiselearning"` instead of `"measure_noise_learning"` gives an inscrutable error.

Of course, on the other hand, dict-based structures are easy to implement and change.

### Version numbers

I am using `VersionNumber` rather than `Int`. There are stories in the software world of headaches that
arise when people want to tighten up loose version number rules.


### Bits and bit-base storage

#### `BitIntegers`

Has poor performance for some operations for large numbers of bits, say
greater than `UInt1024`. I don't know how easy it would be to work around some of these. But
I want to avoid even trying. There is at least one QC Julia package that uses these types
for Pauli operators. For example: `rand(UInt16384)` fails to return in less than a
several of minutes. I did not wait to see if it returns. I think this may be inefficient compilation.
`rand(UInt8192)` takes about a minute for the first one. Then is much faster. But an order of mag
longer than a corresponding array of `UInt64`. Seems to be an algorithmic inefficiency in compiling.

### Pauli operators

I have vendored `PauliOperator` from `QuantumClifford.jl`. The whole package is a bit heavier
than I want at the moment. For most operations (but not all) `PauliOperator` is very fast, competitive
with stim.

Sums of Pauli operators (or tables, etc.) Can be represented efficiently if the storage for each
string is static and of the same size. Then they will be stored inline in a Vector.
If we use dynamic storage, like a `Vector{UInt64}` or `BitArray`, then we probably do not want
a `Vector` of our string type. They would not be stored inline. Unfortunately this story in Julia
is not as good as it could be. There is some discussion about improvements, but they are not here
yet.

Pauli type in `QuantumClifford` has good features, but bad perf in indexing ranges: `data[1:10]`
My current experiment with storing data as a BitArray is 10x faster for this operation

I think the best for the moment is to depend on `QuantumClifford`. It is much bigger than just
the relatively small code supporting Paulis. Some performance issues can be fixed easily outside
of the package.

### Options for primitives

These are in `./src/options.jl`. The Python client uses a type `Unset`, presumably to know whether a param was passed.
This is sometimes useful/necessary. I don't know whether it is in our case. At present, we don't track whether
a param was passed to the constructor, or the default was used. We often use the alias `Opt{T} = Union{T, Nothing}`.
But `nothing` is not always the default. And the user may pass `nothing`, as well. Using a sentinel value, that
is a value that is valid for the data type, but not for the particular application, is also an option. I'm
uncertain which is better. People argue online about it. I am typically favoring `Opt{T}`.

We implemented a macro `@params` to define `struct`s holding parameters. It has all or most features we want, with
no boiler plate.
`@params` depends on a modified and vendored version of Parameters.jl (It would be a good idea to make this a pacakge. But I
don't really want to register it. Furthermore, the Julia culture for alternative registries is (as is the case for Rust, as well) sadly
impovrished.) `parameters2.jl` provides `@with_kw` which automatically makes args to constructors both positional and keyword.
It also easily allows defaults. It also supports validation. For various reasons, related to stalled development,
the original version, Parameters.jl, is not sufficient.

## Load times and [TTFX](https://www.google.com/search?q=julia+ttfx)

At the moment, I am trying vendoring to keep load and TTFX down.
I plan to try Julia package [Extensions](https://pkgdocs.julialang.org/v1/creating-packages/#Conditional-loading-of-code-in-packages-(Extensions))

* Load times. I want to pay attention to load times, because this will be compared to the Python version.
    * `QuantumClifford` -- 1.3s. We use only a small part, `PauliOperator`. So, I vendored this.
    * `Accessors` -- 150ms this makes code much cleaner and easier to both read and write. But it depends
       on `InverseFunctions`, which does compilation.

* `PrecompileTools`. This is working well to make TTFX very low. (EDIT: There has been a regression.
   But the TTFX is still lower than it would be otherwise. I suspect we need more concrete type annotations.)

## Performance

* `LazyString`: remember to use these when throwing exceptions.

### Iterators vs containers

People, including myself, have noted that in Julia we miss the support for iterators that we
find in Rust, and the culture around it. In Julia you have unnecessary allocation in chained
operations on collections. I suspect that part of this difference is due to Julia playing two
roles: one, a programming language; and two, an interactive tool. In the latter, containers
are more convenient.

Still, I'd like to try to use more lazy containers. For example, I am trying this when returning things
from the `Requests` layer. Since this layer is intended to be used primarily
programmatically rather than interactively, you don't lose much convenience in returning,
say `Generator{Vector}`.

## Exceptions

Julia doesn't have a strong culture or concepts of best practices for exceptions.

* Make our own exceptions, or use built in? When to use them?

* Or use an `Option` type?

## Sum/Algebraic types

Speaking of `Option` types. How about a sum type?  These are often really useful.

I have begun to use `SumTypes`, but not for an `Option` type. I am not using `LightSumTypes`.

* [SumTypes.jl](https://github.com/MasonProtter/SumTypes.jl). This seems to have better ergonomics
* [LightSumTypes.jl](https://github.com/JuliaDynamics/LightSumTypes.jl) is very small (50 lines or so) and very
  performant, but lacks features.

There is also Moshi. It's rather heavy, but maybe a better choice.

!!! note
    We use a type `Opt{T} = Union{T, Nothing}`. This is *not* a sum type.

## Code quality and CI

* Testing REST API. I think some kind mocking framework may be necessary.

* [Aqua.jl](https://github.com/JuliaTesting/Aqua.jl) currently in use in this package.
* `JET.jl`. Would be a good idea. It is currently a bit painful to set up.

* [QuantumClifford.jl](https://github.com/QuantumSavory/QuantumClifford.jl)
is an example of a Julia package that uses a [bunch of GH Actions CI tools](https://github.com/QuantumSavory/QuantumClifford.jl/tree/master/.github/workflows) to enforce code quality

* Code formatting. I am trying JuliaFormatter with a custom config. There is a newish package, `Runic.jl`,
  that is a config-less code formatter. I love the idea and tried it. But it indents submodules. The way the
  code is organized, almost every module puts almost all code in a submodule. So almost all code starts with
  a four space indent. With *no* indent, it is really hard to know if you are in the inner or outer module.
  A different way altogether to make symbols private would be great.
  But for now, JuliaFormatter with indent submodules disabled.

```@raw html
<!--  LocalWords:  centric numpy un eg IXYZ PauliOperator Qiskit's BitArray src QASM3 utf
  LocalWords:  QuantumCircuit IDK Precompile precompile jl qiskit precompilation REPL
  LocalWords:  adhoc Dicts dicts noiselearning VersionNumber BitIntegers UInt1024 10x
  LocalWords:  UInt16384 UInt8192 UInt64 vendored QuantumClifford stim perf Paulis 3s
  LocalWords:  TTFX ttfx vendoring Accessors 150ms InverseFunctions PrecompileTools
  LocalWords:  LazyString programmatically LightSumTypes performant GH newish config
  LocalWords:  formatter
-->
```
