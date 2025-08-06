# (C) Copyright IBM 2025.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

module Utils

using ConstructionBase: ConstructionBase
using JSON3: JSON3

using Phase4s: Phase4s
using PauliStrings2: PauliStrings2

using ..QiskitIBMRuntime: QiskitIBMRuntime

export to_dict, to_dict_shallow, to_dict_prune, Iter, showiter

struct Iter{T,GT}
    iter::GT
end
@inline Iter{T}(iter) where {T} = Iter{T,typeof(iter)}(iter)
Base.print(io::IO, ::Iter{T}) where {T} = print(io, "Iter{", T, "}")
Base.show(io::IO, ::MIME"text/plain", iter::Iter) = print(io, iter)
@inline Base.iterate(it::Iter, args...) = iterate(it.iter, args...)
@inline Base.length(it::Iter) = length(it.iter)
@inline Base.eltype(::Iter{T}) where {T} = T
@inline Base.collect(it::Iter) = collect(it.iter)
Base.IteratorSize(::Iter) = Base.SizeUnknown()

"""
    Iter{T}

Iterator over a collection of type `T`.

# Extended help

`Iter` is a  wrapper over another iterator of type `GT`. The full parameterization
is `Iter{T, GT}`, but `GT` is supressed when printing.
The type `GT` may be complicated, and its description uninformative.
In particular, the element type may be difficult to find in the type description,
or may even be absent from it.
`Iter{T}`, on the other hand, has a simple, easy-to-understand, form.
"""
Iter

"""
    showiter([io::IO=stdout], iter)

Call `show` on each element in `iter`, using `MIME"text/plain"`.

A newline is printed after showing each item.

At the Julia repl, `show` with `MIME"text/plain"` is called to display
an object. But for a `Vector` of objects, a more compact display is used.
`showiter` forces the use of `MIME"text/plain"` for each element.

This can be used, for example, with the package `TerminalPager` to browse
a list of objects.
"""
function showiter(io::IO, iter)
    for x in iter
        show(io, MIME"text/plain"(), x)
        println(io)
    end
end

showiter(iter) = showiter(stdout, iter)

# FIXME: find a home for this "declaration"
# Convert an object to a data structure that JSON3 will convert
# to JSON to make a REST API request
function to_rest_api end

to_rest_api(x) = x

# For observables, the coefficient must be real.
# If the API uses Paulis elsewhere, where a complex phase may be needed,
# this will not work. We just take the real part, and trust that the user
# used a real phase.
to_rest_api(p::Phase4s.Phase) = real(p)

function to_rest_api(op::PauliStrings2.PauliOp)
    return Dict(term.pstring => to_rest_api(term.coeff) for term in op.terms)
end

"""
    @pretty_show(typ)

Writes methods to pretty-print fields and values of objects of type `typ` at the REPL.

This writes methods for `Base.show` to print field names and values with indentation
and newlines. It also writes a method to track indentation when objects are nested.
That is, when pretty-showified objects are nested, they are pretty-printed with appropriate indentation.

If a field of a pretty-showified object is of a type that is not pretty-showified, then
this field is printed normally (according to whatever method of `Base.show` would be invoked
if it were not in a field)
"""
macro pretty_show(typ, opts...)
    dict = Dict{Any,Any}()
    good_keys = (:show_name, :nonothing)
    for opt in opts
        isa(opt, Expr) && opt.head == :(=) ||
            throw(ArgumentError("Expecting keyword argument"))
        (k, v) = (opt.args...,)
        k in good_keys || throw(ArgumentError("Unrecognized keyword argument $k"))
        dict[k] = v
    end
    show_name = get(dict, :show_name, nothing)
    nonothing = get(dict, :nonothing, false)
    return esc(
        quote
            function Base.show(io::IO, ::MIME"text/plain", p::$typ)
                #              return QiskitIBMRuntime.Utils._show(io, p; newlines=true, show_name=$show_name)
                return Utils._show(
                    io,
                    p;
                    newlines=true,
                    show_name=$show_name,
                    nonothing=$nonothing,
                )
            end
            #QiskitIBMRuntime.Utils.want_pretty_show(::Type{T}) where {T<:$typ} = true
            Utils.want_pretty_show(::Type{T}) where {T<:$typ} = true
        end,
    )
end

# Define a method for a type T that returns `true` in order
# to call `_show` on a field, when `_show` is called on the parent type.
# By default, `_show` calls `Base.show` on fields.
function want_pretty_show(::Type{T}) where {T}
    return false
end

# Show object optionally with field_names and newlines between fields.
function _show(
    io::IO,
    object;
    field_names=true,
    newlines=false,
    indent=0,
    show_name=nothing,
    nonothing=false,
) # printfields::Bool=false)
    T = typeof(object)
    show_name = isnothing(show_name) ? T : show_name
    #    fnames = fieldnames(T)
    fnames = propertynames(object)

    outer_indent_str = " "^indent
    inner_indent = 2 + indent
    showfunc = print
    #    showfunc(io, outer_indent_str, show_name, "(")
    showfunc(io, show_name, "(")
    let countfields = 0
        for field in fnames
            subobj = getproperty(object, field)
            nonothing && isnothing(subobj) && continue
            countfields += 1
        end
        if iszero(countfields)
            print(io, ")")
            return nothing
        end
    end # let
    if newlines
        println(io)
    end
    for (n, field) in enumerate(fnames)
        subobj = getproperty(object, field)
        nonothing && isnothing(subobj) && continue
        newlines && showfunc(io, " "^inner_indent)
        if field_names
            showfunc(io, field, " = ")
        end
        if isa(subobj, Array)
            print(io, subobj)
        else
            if want_pretty_show(typeof(subobj))
                _show(io, subobj; field_names, newlines, indent=inner_indent, nonothing)
            else
                show(io, MIME"text/plain"(), subobj)
            end
        end
        if n != length(fnames)
            if newlines
                showfunc(io, ",")
            else
                showfunc(io, ", ")
            end
        end
        if newlines
            println(io)
        end
    end
    showfunc(io, outer_indent_str, ")")
    return nothing
end

# Show obj, omitting fields with value `nothing`.
abbrev(obj) = abbrev(stdout, obj)
function abbrev(io::IO, obj; field_names=true, newlines=true, indent=0, show_name=nothing)
    return _show(io, obj; field_names, newlines, show_name, indent, nonothing=true)
end

function to_dict_shallow(obj; filt=Returns(true), mapf=identity)
    nt = ConstructionBase.getfields(obj)
    res = Iterators.filter(filt, pairs(nt))
    return Dict(Iterators.filter(filt, map(mapf, res)))
end

# Deep to_dict
"""
    to_dict(obj)

Convert `obj` to a `Dict`.

`to_dict` is called recursively on all fields of `obj` that are struct types with one or more fields.
"""
function to_dict(obj; filt=Returns(true))
    mapf = function (x)
        val = x[2]
        iszero(nfields(val)) && return x
        isempty(ConstructionBase.getproperties(val)) && return x
        if isstructtype(typeof(val))
            dict_ = to_dict(val; filt)
            isempty(dict_) && return x[1] => nothing
            return x[1] => dict_
        end
        return x
    end
    return to_dict_shallow(obj; filt, mapf)
end

function to_dict_prune(obj)
    filt = x -> !isnothing(x[2])
    return to_dict(obj; filt)
end

# Convert `dict` to a pretty JSON string
function pretty_json(dict::Dict)
    return pretty_json(JSON3.write(dict))
end

# Pretty-format json that is already a string
function pretty_json(json::AbstractString)
    io = IOBuffer()
    JSON3.pretty(io, json)
    return String(take!(io))
end

function normalize_real_name(name::AbstractString)
    (startswith(name, "ibm_") || startswith(name, "test_")) && return name
    startswith(name, "fake_") &&
        throw(ArgumentError("Can't normalize real-machine name starting with \"fake_\""))
    return "ibm_" * name
end

function normalize_fake_name(name::AbstractString)
    startswith(name, "fake_") && return name
    if (startswith(name, "ibm_") || startswith(name, "test_"))
        throw(
            ArgumentError(
                "Can't normlize fake-machine name that starts with \"ibm_\"  or \"test_\"",
            ),
        )
    end
    return "fake_" * name
end

function try_pkg_version(pkg_name::Symbol)
    isdefined(Main, pkg_name) || return nothing
    @eval pkgversion(Main.$pkg_name)
end

function version_info()
    qiskit_runtime = pkgversion(QiskitIBMRuntime)
    qiskit_runtime_x = try_pkg_version(:QiskitIBMRuntimeX)
    if isnothing(qiskit_runtime_x)
        return (qiskit_runtime=qiskit_runtime,)
    end
    pyversions = Main.QiskitIBMRuntimeX.Utils.version_info()
    v = (qiskit_runtime=qiskit_runtime, qiskit_runtime_x=qiskit_runtime_x)
    return merge(v, pyversions)
end

end # module Utils
