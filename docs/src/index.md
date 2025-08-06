# QiskitIBMRuntime.jl

!!! warning
    This documentation is **not** for the standard client [qiskit-ibm-runtime](https://github.com/Qiskit/qiskit-ibm-runtime) to
    the [Qiskit Runtime REST API](https://docs.quantum.ibm.com/api/runtime)

    To find information on the easiest way to use the Qiskit Runtime use this link:

    [qiskit-ibm-runtime](https://github.com/Qiskit/qiskit-ibm-runtime)

    The documentation you are reading now is only for the **highly experimental Julia-language** client, not for the
    [Python-langauge client](https://github.com/Qiskit/qiskit-ibm-runtime).

!!! warning
    Documentation pages for `QiskitIBMRuntime.jl` are a WIP.

```@meta
DocTestSetup = quote
    using QiskitIBMRuntime
end
```

## Contents

See also the [Development notes](@ref).

```@contents
Pages = ["index.md", "tutorial.md", "accounts.md", "env_vars.md", "requests.md", "ids.md", "theindex.md"]
Depth = 2
```

# Introduction

```@meta
DocTestSetup = quote
  set_env!(:QISKIT_USER_DIR, joinpath(pkgdir(QiskitIBMRuntime), "test", ".qiskit"))
end
```

```@autodocs
Modules = [QiskitIBMRuntime]
```

# Jobs

```@autodocs
Modules = [QiskitIBMRuntime.Jobs]
```

# Backends

```@autodocs
Modules = [QiskitIBMRuntime.Backends]
```

```@meta
DocTestSetup = quote
    set_env!(:QISKIT_IBM_TOKEN, nothing)
    set_env!(:QISKIT_IBM_INSTANCE, nothing)
end
```

# Instances

```@autodocs
Modules = [QiskitIBMRuntime.Instances]
```

```@meta
DocTestSetup = quote
    delete!(ENV, "QISKIT_USER_DIR")
end
```

```@meta
DocTestSetup = nothing
```

# PUBs

```@autodocs
Modules = [QiskitIBMRuntime.PUBs]
```

# Circuits

```@autodocs
Modules = [QiskitIBMRuntime.Circuits]
```

# Options

```@autodocs
Modules = [QiskitIBMRuntime.Options]
```

```@meta
CurrentModule = QiskitIBMRuntime
```
