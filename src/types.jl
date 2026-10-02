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

  - `arguments`: an ordered `Vector` of positional argument values --
    duplicates and order are preserved;
  - `properties`: an `OrderedDict` of `key => value` pairs (rightmost wins);
  - `body`: an `OrderedDict` of children keyed by name (last occurrence wins);
  - `children`: an ordered `Vector` of `(name, node)` pairs -- duplicates and
    order are preserved.

Reach the collections with `arguments`, `properties` and `children`.
`k[:name]` reaches a child, `k[1]` an argument by position, `k.name` a
property value (`missing` when absent), and `name in k` tests argument
membership.  `show` serialises a node back to KDL.
"""
mutable struct KDLNode
    arguments  :: Vector{Any}
    properties :: OrderedDict{Any,Any}
    body       :: OrderedDict{Any,KDLNode}
    children   :: Vector{Pair{Any,KDLNode}}

    KDLNode() = new(Any[], OrderedDict{Any,Any}(), OrderedDict{Any,KDLNode}(),
                    Pair{Any,KDLNode}[])

    KDLNode(args::AbstractVector, props::AbstractDict) =
        new(collect(Any, args), OrderedDict{Any,Any}(props),
            OrderedDict{Any,KDLNode}(), Pair{Any,KDLNode}[])

    KDLNode(kids::Pair...) =
        new(Any[], OrderedDict{Any,Any}(), OrderedDict{Any,KDLNode}(kids...),
            Pair{Any,KDLNode}[kids...])

    KDLNode(arguments, properties, body, children) =
        new(arguments, properties, body, children)
end

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

The children of `k`, as an ordered `Vector` of `(name, node)` pairs.
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

# The stored key matching `key`, treating a Symbol and its string form as the
# same name.  Returns `nothing` when there is no match.
function kdl_key(d, key)
    haskey(d, key) && return key
    key isa Symbol         && haskey(d, string(key)) && return string(key)
    key isa AbstractString && haskey(d, Symbol(key)) && return Symbol(key)
    return nothing
end

"""
    k.name

The child node named `name`.
"""
function Base.getproperty(k::KDLNode, name::Symbol)
    body = getfield(k, :body)
    key = kdl_key(body, name)
    key === nothing && throw(FieldError(KDLNode, name))
    body[key]
end

"""
    k.name = node

Add or replace the child node named `name`.
"""
function Base.setproperty!(k::KDLNode, name::Symbol, v)
    body = getfield(k, :body)
    kids = getfield(k, :children)
    key = something(kdl_key(body, name), name)
    body[key] = v
    # keep the ordered children list in sync: replace the last occurrence of
    # the name, or append a new one
    idx = findlast(p -> first(p) == key, kids)
    if idx === nothing
        push!(kids, key => v)
    else
        kids[idx] = key => v
    end
    v
end

"""
    propertynames(k::KDLNode)

The child names of `k`, as a `Tuple`.  Drives tab completion on a parsed
node.
"""
Base.propertynames(k::KDLNode) =
    Tuple(name isa Symbol ? name : Symbol(name) for name in keys(getfield(k, :body)))

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
Base.haskey(k::KDLNode, i) = kdl_key(getfield(k, :properties), i) !== nothing ||
                             kdl_key(getfield(k, :body), i) !== nothing

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
    empty!(getfield(k, :body))
    empty!(getfield(k, :children))
    k
end

"""
    merge(j::KDLNode, k::KDLNode)

A new node combining the arguments, properties and children of `j` and `k`.
Arguments and children are concatenated; properties and name-keyed children
are merged with `k` winning on clashes.
"""
Base.merge(j::KDLNode, k::KDLNode) =
    KDLNode(vcat(getfield(j, :arguments), getfield(k, :arguments)),
            merge(copy(getfield(j, :properties)), copy(getfield(k, :properties))),
            merge(copy(getfield(j, :body)), copy(getfield(k, :body))),
            vcat(getfield(j, :children), getfield(k, :children)))

"""
    merge!(j::KDLNode, k::KDLNode)

Merge `k` into `j` in place and return `j`.
"""
function Base.merge!(j::KDLNode, k::KDLNode)
    append!(getfield(j, :arguments), getfield(k, :arguments))
    merge!(getfield(j, :properties), getfield(k, :properties))
    merge!(getfield(j, :body), getfield(k, :body))
    append!(getfield(j, :children), getfield(k, :children))
    j
end
