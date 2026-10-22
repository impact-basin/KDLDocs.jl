# KDLDocs.jl

[KDL](https://kdl.dev) is a node-oriented document
language similar to XML and JSON. This package implements the [KDL 2.0
specification](https://github.com/kdl-org/kdl/blob/main/SPEC.md), using the
[PikaMacros](https://github.com/impact-basin/PikaMacros.jl) /
[PikaParser](https://github.com/LCSB-BioCore/PikaParser.jl) parser toolkit.

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

Each KDL node can have arguments ("args"), properties ("props"), or children.  Arguments are position-dependent values, e.g. `1 2 3` in `foo 1 2 3` for the node `foo`. Properties are position-independent assigned values, e.g.  (`foo example=#true`).

Children are written in curly braces and can be arbitrarily nested:
in their own right, e.g.

```kdl
foo 1 2 3 {
    bar "baz" extra symbol arguments
    baz 7 8 9 {
        qux "topsecret" different=#true
    }
}
```

KQL allows for querying documents via [`@query`](@ref):

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl"""
       package {
           name my_pkg
       }
       """;

julia> @query doc package
1-element Vector{KDLNode}:
 package {
        name my_pkg 
 }
```

A `begin ... end` block runs several queries and returns a tuple:

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl"""foo 1 2 3 {
    bar "baz" extra symbol arguments
    baz 7 8 9 {
        qux "string" other fields
    }
}"""

juila> bar, baz = @query doc begin
    bar
    baz    
end

julia> bar
1-element Vector{KDLNode}:
 bar "baz" extra symbol arguments 

julia> baz
1-element Vector{KDLNode}:
 baz 7 8 9 {
        qux "string" other fields 
}
```

## Pages

  - [API Reference](@ref) -- the documented public interface.
