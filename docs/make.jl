using Documenter

# This may be a red herring, since, for practical purposes, you have to dev the
# packge anyway.
# push!(LOAD_PATH, "..")

import Pkg
Pkg.develop(path="..")

# First, you *must* dev QiskitRuntime:
# Hopefully, the lines above these comments should be sufficient. If not...
#
# `(docs) pkg> dev path/to/this/package/QiskitRuntime`
# Furthermore, often, if the `Project.toml` is updated, the documentation fails to build unless I
# refresh the dev like this:
# `(docs) pkg> rm QiskitRuntime
# `(docs) pkg> dev path/to/this/package/QiskitRuntime`

# One way to build docs.
# cd to this dir, `./docs/`.
# Run `julia --project="." make.jl`
#
# Note: Usually, this works for dev'ing the package as well.
# `(docs) pkg> dev ..

using QiskitRuntime

# This sets current module for running doc tests.
# We want to set it to the top-level module.
Documenter.DocMeta.setdocmeta!(QiskitRuntime, :DocTestSetup, :(using QiskitRuntime); recursive=true)

makedocs(
    sitename = "QiskitRuntime.jl",
    format = Documenter.HTML(),
    modules = [QiskitRuntime, QiskitRuntime.Requests],
    doctest = false, # Don't run tests. We run them when running unit tests instead.
    warnonly = [:missing_docs], # Don't fail on a lot of things, like missing doc strings.
    authors = "John Lapeyre",
    pages = [
        "Introduction" => "index.md",
        "Tutorial" => "tutorial.md",
        "Accounts" => "accounts.md",
        "Environment Variables" => "env_vars.md",
        "Requests" => "requests.md",
        "Id Numbers and Tokens" => "ids.md",
        "PythonCall and other packages" => "python.md",
        "Development notes" => "dev_notes.md",
        "Index" => "theindex.md",
    ],
    # Following disables remote links, which needs a publically accessible URL.
    # You must do this for a private github repo.
    # remotes = nothing,
    # Following prob not neccesary if remotes=nothing not present
    # repo = Documenter.Remotes.GitHub("jlapeyre", "QiskitRuntime.jl"),
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
deploydocs(
    repo = "github.com/jlapeyre/QiskitRuntime.jl.git"
)
