# Accounts

```@raw html
<!--
I wish there were a way to put a section, such as "Credentials file" (below) in
a doc string in the source. For example in the docstring for `modules Account`.
I *can* put it there. But it is not integrated semantically into the docs. And
it is not rendered well, either.
-->
```

## [Credentials file](@id credentials_file)

!!! danger
    Account credentials are saved in plain text, so only do so if you are using a trusted device.

In order to use the Qiskit Runtime service you need an account, and credentials for authentication.

By default, the credentials are saved in the file
```sh
$HOME/.qiskit/qiskit-ibm.json
```
where `$HOME` is your home directory. `QiskitRuntime` can read this file, but cannot write it.
You can create it with the Python client and/or edit it by hand.

Which account is used for credentials may also be controlled with [environment variables](@ref environment_variables)

!!! info
    We want to consistently use the term "credentials file" when referring to the file storing credentials
    for accounts. However, the word "account" is sometimes used. For example, the credentials file is read,
    and entries decoded into [`QuantumAccount`](@ref) objects.

    The Python code in [qiskit-ibm-runtime](https://github.com/Qiskit/qiskit-ibm-runtime) sometimes uses
    the word fragment "config" in variables related to the credentials file, and its containing directory.
    We do not follow this convention.

```@meta
DocTestSetup = quote
  set_env!(:QISKIT_USER_DIR, joinpath(pkgdir(QiskitRuntime), "test", ".qiskit"))
end
```

## Functions and types

```@autodocs
Modules = [QiskitRuntime.Accounts]
```
