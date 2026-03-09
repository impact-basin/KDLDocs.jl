# KDLDocs.jl -- KDL Documents in Julia

This package is mainly a proving ground for a PikaParser.jl front-end.

You are, however, welcome to use it if you so desire, under the MIT license.

## Reading KDL

```julia
k = kdl(str)
# ... or ...
k = kdl"""
node example=#true {
    foo 1 2 3
    bar 4 5 6 {
        alpha
        beta
        gamma
    }
}
"""
```

## Working with KDL

Child nodes are accessible by normal indexing, which may be chained:

```julia
k[:node, :bar] # => KDLNode
```

The child node keys may be examined by passing no arguments to `getindex()`:

```julia
k[:node, :bar][] # => [:alpha, :beta, :gamma]
```

We may add another child with `setindex!()`:

```julia
k[:node, :bar, :delta] = KDLNode(missing, missing)
```

Arguments are accessible by using parentheses:

```julia
k[:node]() # => [:example]
```

```julia
k[:node](:example) # => true
```

To set an argument, pass an additional argument:

```julia
k[:node](:example, false) # => node example=#false ...
```

## Writing KDL

Base.show() gives you back the raw KDL:

```julia
julia> k
node example=#true {
    foo 1 2 3
    bar 4 5 6 {
        alpha
        beta
        gamma
    }
}
```
