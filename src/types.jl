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

"""
    k.name

The value of the property `name` of `k`, or `missing` when absent.
"""
function Base.getproperty(k::KDLNode, name::Symbol)
    props = getfield(k, :properties)
    haskey(props, name) ? props[name] : missing
end

"""
    k.name = v

Set the property `name` of `k` to `v`.  A `missing` value is rejected, since
KDL has no missing value.
"""
function Base.setproperty!(k::KDLNode, name::Symbol, v)
    ismissing(v) &&
        throw(ArgumentError("KDL has no missing value; delete the property instead"))
    getfield(k, :properties)[name] = v
    v
end

"""
    propertynames(k::KDLNode)

The Symbol property keys of `k`, in insertion order.  Drives tab completion on
a parsed node.
"""
Base.propertynames(k::KDLNode) =
    Tuple(name for name in keys(getfield(k, :properties)) if name isa Symbol)

"""
    x in k::KDLNode

Whether `x` is one of the positional arguments of `k`.  Membership uses
`isequal`, so `missing in k` is `false` and `NaN in k` works.
"""
Base.in(x, k::KDLNode) = any(y -> isequal(x, y), getfield(k, :arguments))

"""
    k[i]

The child node named `i`.

    k[i::Integer]

The `i`-th positional argument of `k`.

    k[i...]

Chained access, e.g. `k[:a, 1]` (child `:a`, then its first argument).

    k[]

The names of the child nodes of `k`, as a `Tuple`.
"""
Base.getindex(k :: KDLNode, i :: Integer) = getfield(k, :arguments)[i]
Base.getindex(k :: KDLNode, i :: Union{Symbol,AbstractString}) = getfield(k, :body)[i]

function Base.getindex(k :: KDLNode, i :: Union{Vector,Tuple})
    isempty(i) && error("Zero-length index for $k")
    length(i) == 1 && return k[i[1]]
    return k[i[1]][i[2:end]]
end

Base.getindex(k :: KDLNode, i...) = k[i]
Base.getindex(k :: KDLNode)       = Tuple(keys(getfield(k, :body)))

"""
    haskey(k::KDLNode, i)

Whether `k` has a child or property named `i`.  Positional arguments are
unnamed; test them with `i in k`.
"""
Base.haskey(k :: KDLNode, i) = haskey(getfield(k, :properties), i) ||
                               haskey(getfield(k, :body), i)

"""
    k[i] = v

Replace the `i`-th positional argument of `k`.

    k[name] = node

Add or replace the child node named `name`, keeping the ordered `children`
list in sync.  Chained and vector/tuple index forms work as well.
"""
function Base.setindex!(k :: KDLNode, v, i :: Integer)
    getfield(k, :arguments)[i] = v
end

function Base.setindex!(k :: KDLNode, v, i :: Union{Symbol,AbstractString})
    getfield(k, :body)[i] = v
    kids = getfield(k, :children)
    # keep the ordered children list in sync: replace the last occurrence of
    # the name, or append a new one
    idx = findlast(p -> first(p) == i, kids)
    if idx === nothing
        push!(kids, i => v)
    else
        kids[idx] = i => v
    end
    v
end

function Base.setindex!(k :: KDLNode, v, i :: Union{Vector,Tuple})
    isempty(i) && error("Zero-length index for $k")
    length(i) == 1 && return setindex!(k, v, i[1])
    return setindex!(k[i[1]], v, i[2:end])
end

# chained setindex!, e.g. k[:a, :b] = node  (lowers to setindex!(k, node, :a, :b))
Base.setindex!(k::KDLNode, v, i1, i2, rest...) = setindex!(k[i1], v, i2, rest...)

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
