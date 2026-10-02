# KDLDocs.jl

*KDL Documents in Julia.*

[KDL](https://kdl.dev) (KDL Document Language) is a node-oriented document
language similar to XML and JSON. This package implements the [KDL 2.0
specification](https://github.com/kdl-org/kdl/blob/main/SPEC.md), using the
[PikaMacros](https://github.com/PikaTools/PikaMacros.jl) /
[PikaParser](https://github.com/PikaTools/PikaParser.jl) parser toolkit.

## Quick start

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl"""
       node example=#true {
           foo 1 2 3
           bar 4 5 6
       }
       """;

julia> doc.node[:example]
true

julia> doc.node.foo[1]
1

julia> arguments(doc.node.foo)
3-element Vector{Any}:
 1
 2
 3
```

Each KDL node has three kinds of field: arguments, properties, and children.
Arguments and properties sit before the optional block; arguments are
position-dependent values (`1 2 3` in `foo 1 2 3`), while properties are
position-independent assigned values (`example=#true`). Children are full
nodes, and they nest inside the braces.

`kdl()` parses a document into a [`KDLNode`](@ref). Children read as fields
(`doc.node`), properties and arguments by index (`doc.node[:example]`,
`doc.node.foo[1]`), and an absent property is `missing`. `Base.show`
serialises a node back to KDL, so the printed form round-trips:

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl"""
       node example=#true {
           foo 1 2 3
       }
       """;

julia> kdl(sprint(show, doc)) isa KDLNode
true
```

## Pages

  - [Usage](@ref) -- parsing, navigation, mutation, serialisation, and errors.
  - [Architecture](@ref) -- how the parser works, and the `KDLNode` data model.
  - [API Reference](@ref) -- the documented public interface.
