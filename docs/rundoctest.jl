using QiskitRuntime

# This code is meant for running the doctests from the Julia REPL
# Or as a script.
# For example:
#
# julia> include("rundoctests.jl")
#
# This runs doctests much more quickly than when building docs and when
# running the test suite.

try
    DocMeta
catch
    using Documenter; DocMeta.setdocmeta!(QiskitRuntime, :DocTestSetup, :(using QiskitRuntime); recursive=true);
end

# For testing we set some env vars, including for using  a `.qiskit/` in `./test` rather
# than the home directory. We want to unset these both before after running the doc tests.
# There are various ways to do this. They work differently depending on whether the docs are
# being built, or the testsuite is running, or you use a script. So we are zealous in
# trying to unset them. People like the convenience of this global state. But it causes headaches.
function clean_env()
    for k in ("QISKIT_CONFIG_DIR", "QISKIT_IBM_TOKEN", "QISKIT_IBM_INSTANCE")
        if !isnothing(get(ENV, k, nothing))
            delete!(ENV, "QISKIT_CONFIG_DIR")
        end
    end
end

clean_env()

ENV["QISKIT_CONFIG_DIR"] = joinpath(pkgdir(QiskitRuntime), "test", ".qiskit")

try
    Documenter.doctest(QiskitRuntime)
catch
    println("Doc tests failed")
end

clean_env()

nothing;
