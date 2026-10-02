# API Reference

## Nodes

```@docs
KDLNode
```

## Collections

```@docs
arguments
properties
children
```

## Parsing

```@docs
kdl
@kdl_str
KDLDocs.kdl_read
KDLParseError
```

## Navigating and reading

```@docs
Base.getindex(k::KDLNode, i::Integer)
Base.getproperty(k::KDLNode, name::Symbol)
Base.propertynames(k::KDLNode)
Base.in(x, k::KDLNode)
Base.haskey(k::KDLNode, i)
```

## Mutating

```@docs
Base.setindex!(k::KDLNode, v, i::Integer)
Base.setproperty!(k::KDLNode, name::Symbol, v)
Base.push!(k::KDLNode, v)
Base.empty!(k::KDLNode)
Base.merge(j::KDLNode, k::KDLNode)
Base.merge!(j::KDLNode, k::KDLNode)
```

## Serialising

```@docs
Base.show(io::IO, k::KDLNode)
Base.write(io::IO, k::KDLNode)
```
