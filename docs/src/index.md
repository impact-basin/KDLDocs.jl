# KDLDocs.jl

*KDL Documents in Julia.*

[KDL](https://kdl.dev) (KDL Document Language) is a node-oriented document
language whose niche overlaps with XML and JSON: you can use it as a
configuration language or as a data exchange/storage format.  This package
implements the [KDL 2.0 specification](https://github.com/kdl-org/kdl/blob/main/SPEC.md),
using the [PikaMacros](https://github.com/PikaTools/PikaMacros.jl) /
[PikaParser](https://github.com/PikaTools/PikaParser.jl) parser toolkit.

## Quick start

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl"node example=#true { foo 1 2 3; bar 4 5 6 }";

julia> doc[:node].example
true

julia> doc[:node, :foo][1]
1

julia> arguments(doc[:node, :foo]) == [1, 2, 3]
true

julia> doc[:node, :bar] isa KDLNode
true
```

`kdl` parses a document into a [`KDLNode`](@ref).  Children are reached by
name, positional arguments by integer, properties by field, and `show`
serialises a node back to KDL.

The printed form round-trips:

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl("node example=#true { foo 1 2 3 }");

julia> kdl(sprint(show, doc)) isa KDLNode
true
```

## Pages

  - [Usage](@ref) -- parsing, navigation, mutation, serialisation, and errors.
  - [Architecture](@ref) -- how the parser works, and the `KDLNode` data model.
  - [API Reference](@ref) -- the documented public interface.
