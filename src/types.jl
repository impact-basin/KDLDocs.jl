# Core types for KDL documents.

"""
    KDLParseError(msg)

Raised when a KDL document cannot be parsed, or violates a semantic rule of
the specification (reserved identifier, invalid escape, multi-line string
structure, disallowed code point, ...).
"""
struct KDLParseError <: Exception
    msg :: String
end
Base.showerror(io::IO, e::KDLParseError) = print(io, "KDL parse error: ", e.msg)

"""
    KDLNode

A node in a parsed KDL document.

A node has:

  - `name`: its name -- a `Symbol` for a bare identifier, a `String` for a
    quoted or raw string, and `nothing` for a document root (the unnamed
    container of top-level nodes);
  - `arguments`: an ordered `Vector` of positional argument values --
    duplicates and order are preserved;
  - `properties`: an `OrderedDict` of `key => value` pairs (rightmost wins);
  - `children`: an ordered `Vector` of child nodes -- duplicates and order are
    preserved.

Reach the collections with `arguments`, `properties` and `children`, and the
node's own name with `nameof`.  `k.name` reaches a child, `k[1]` an argument
by position, `k[:key]` a property value (`missing` when absent), and `name in
k` tests argument membership.  `show` serialises a node back to KDL.
"""
mutable struct KDLNode
    name       :: Union{Nothing, Symbol, String}
    arguments  :: Vector{Any}
    properties :: OrderedDict{Any, Any}
    children   :: Vector{KDLNode}

    KDLNode() = new(nothing, Any[], OrderedDict{Any,Any}(), KDLNode[])

    KDLNode(name::Union{Nothing, Symbol, String}) =
        new(name, Any[], OrderedDict{Any,Any}(), KDLNode[])

    KDLNode(args::AbstractVector, props::AbstractDict) =
        new(nothing, collect(Any, args), OrderedDict{Any,Any}(props), KDLNode[])

    KDLNode(name::Union{Nothing, Symbol, String}, args::AbstractVector,
            props::AbstractDict, kids::AbstractVector) =
        new(name, collect(Any, args), OrderedDict{Any,Any}(props),
            collect(KDLNode, kids))

    function KDLNode(kids::Pair...)
        k = new(nothing, Any[], OrderedDict{Any,Any}(), KDLNode[])
        for (name, child) in kids
            child isa KDLNode ||
                throw(ArgumentError("children must be KDLNode values"))
            setfield!(child, :name, name)
            push!(getfield(k, :children), child)
        end
        k
    end
end

"""
    nameof(k::KDLNode)

The name of node `k`: a `Symbol` for a bare identifier, a `String` for a
quoted or raw string, or `nothing` for a document (the unnamed root).
"""
Base.nameof(k::KDLNode) = getfield(k, :name)

"""
    arguments(k::KDLNode)

The ordered positional arguments of `k`.
"""
arguments(k::KDLNode) = getfield(k, :arguments)

"""
    properties(k::KDLNode)

The properties of `k`, as an `OrderedDict` of `key => value`.
"""
properties(k::KDLNode) = getfield(k, :properties)

"""
    children(k::KDLNode)

The children of `k`, as an ordered `Vector{KDLNode}` in document order.
Duplicate names are kept; each child knows its own name via `nameof`.
"""
children(k::KDLNode) = getfield(k, :children)

# Julia 1.11 has no Base.FieldError.  Define the same shape there so a missing
# child throws one type on every supported version.
if !isdefined(Base, :FieldError)
    struct FieldError <: Exception
        type  :: Type
        field :: Symbol
    end
    Base.showerror(io::IO, e::FieldError) =
        print(io, "FieldError: type ", e.type, " has no field `", e.field, "`")
end

# Whether the stored node name `n` matches the lookup key `key`, treating a
# Symbol and its string form as the same name.
function name_key_eq(n, key)
    n === nothing && return false
    n === key && return true
    n isa Symbol         && key isa AbstractString && return string(n) == key
    n isa AbstractString && key isa Symbol         && return n == string(key)
    return false
end

# The stored property key matching `key`, treating a Symbol and its string
# form as the same name.  Returns `nothing` when there is no match.
function kdl_key(d, key)
    haskey(d, key) && return key
    key isa Symbol         && haskey(d, string(key)) && return string(key)
    key isa AbstractString && haskey(d, Symbol(key)) && return Symbol(key)
    return nothing
end

"""
    k.name

The child node named `name`.  For duplicate names, the last occurrence.
"""
function Base.getproperty(k::KDLNode, name::Symbol)
    kids = getfield(k, :children)
    idx = findlast(child -> name_key_eq(nameof(child), name), kids)
    idx === nothing && throw(FieldError(KDLNode, name))
    kids[idx]
end

"""
    k.name = node

Add or replace the child node named `name`, giving `node` that name.
"""
function Base.setproperty!(k::KDLNode, name::Symbol, v)
    v isa KDLNode || throw(ArgumentError("children must be KDLNode values"))
    kids = getfield(k, :children)
    idx = findlast(child -> name_key_eq(nameof(child), name), kids)
    if idx === nothing
        setfield!(v, :name, name)
        push!(kids, v)
    else
        # keep the spelling of the child already stored under this name
        setfield!(v, :name, nameof(kids[idx]))
        kids[idx] = v
    end
    v
end

"""
    propertynames(k::KDLNode)

The child names of `k`, as a `Tuple` of unique names in document order.
Drives tab completion on a parsed node.
"""
function Base.propertynames(k::KDLNode)
    names = Symbol[]
    for child in getfield(k, :children)
        nameof(child) === nothing && continue
        name = Symbol(nameof(child))
        any(==(name), names) || push!(names, name)
    end
    Tuple(names)
end

"""
    x in k::KDLNode

Whether `x` is one of the positional arguments of `k`.  Membership uses
`isequal`, so `missing in k` is `false` and `NaN in k` works.
"""
Base.in(x, k::KDLNode) = any(y -> isequal(x, y), getfield(k, :arguments))

"""
    k[key]

The value of the property `key` of `k`, or `missing` when absent.  `key` may
be a `Symbol` or a `String`, and the two forms name the same property.
"""
function Base.getindex(k::KDLNode, key::Union{Symbol,AbstractString})
    props = getfield(k, :properties)
    stored = kdl_key(props, key)
    stored === nothing ? missing : props[stored]
end

"""
    k[i::Integer]

The `i`-th positional argument of `k`.
"""
Base.getindex(k::KDLNode, i::Integer) = getfield(k, :arguments)[i]

"""
    k[key] = v

Set the property `key` of `k` to `v`.  A `missing` value is rejected, since KDL
has no missing value.
"""
function Base.setindex!(k::KDLNode, v, key::Union{Symbol,AbstractString})
    ismissing(v) &&
        throw(ArgumentError("KDL has no missing value; delete the property instead"))
    props = getfield(k, :properties)
    props[something(kdl_key(props, key), key)] = v
    v
end

"""
    k[i::Integer] = v

Replace the `i`-th positional argument of `k`.
"""
function Base.setindex!(k::KDLNode, v, i::Integer)
    getfield(k, :arguments)[i] = v
end

"""
    haskey(k::KDLNode, i)

Whether `k` has a child or property named `i`.  Positional arguments are
unnamed; test them with `i in k`.
"""
Base.haskey(k::KDLNode, i) =
    kdl_key(getfield(k, :properties), i) !== nothing ||
    any(child -> name_key_eq(nameof(child), i), getfield(k, :children))

"""
    push!(k::KDLNode, v)

Append the positional argument `v` to `k`, returning `k`.
"""
Base.push!(k::KDLNode, v) = (push!(getfield(k, :arguments), v); k)

"""
    empty!(k::KDLNode)

Remove all arguments, properties and children of `k`, returning `k`.
"""
function Base.empty!(k::KDLNode)
    empty!(getfield(k, :arguments))
    empty!(getfield(k, :properties))
    empty!(getfield(k, :children))
    k
end

"""
    merge(j::KDLNode, k::KDLNode)

A new node combining the arguments, properties and children of `j` and `k`.
Arguments and children are concatenated; properties are merged with `k`
winning on clashes, and the result takes `k`'s name (right operand wins, as
`Base.merge` does for dictionaries).
"""
Base.merge(j::KDLNode, k::KDLNode) =
    KDLNode(nameof(k),
            vcat(getfield(j, :arguments), getfield(k, :arguments)),
            merge(copy(getfield(j, :properties)), copy(getfield(k, :properties))),
            vcat(getfield(j, :children), getfield(k, :children)))

"""
    merge!(j::KDLNode, k::KDLNode)

Merge `k` into `j` in place and return `j`.  As with `merge`, `k`'s name wins.
"""
function Base.merge!(j::KDLNode, k::KDLNode)
    append!(getfield(j, :arguments), getfield(k, :arguments))
    merge!(getfield(j, :properties), getfield(k, :properties))
    append!(getfield(j, :children), getfield(k, :children))
    setfield!(j, :name, nameof(k))
    j
end
