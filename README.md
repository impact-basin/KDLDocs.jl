# KDLDocs.jl

A parser for the [KDL Document Language](https://kdl.dev), built on
[PikaMacros](https://github.com/PikaTools/PikaMacros.jl) and
[PikaParser](https://github.com/PikaTools/PikaParser.jl).

## Quick start

```julia
using KDLDocs

doc = kdl"""
node example=#true {
    foo 1 2 3
    bar 4 5 6
}
"""

doc[:node].example           # true
doc[:node, :foo][1]          # 1
arguments(doc[:node, :foo])  # [1, 2, 3]
```

## Documentation

The full guide lives at <https://impact-basin.github.io/KDLDocs.jl/>: navigation
and mutation, the architecture, and the API reference.

## Licence

MIT.  See [LICENSE](LICENSE).
