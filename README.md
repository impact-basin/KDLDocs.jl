# KDLDocs.jl

A parser for the [KDL Document Language](https://kdl.dev), using
[PikaMacros](https://github.com/PikaTools/PikaMacros.jl) and
[PikaParser](https://github.com/PikaTools/PikaParser.jl).

This repo is verified against the test cases in [kdl-test](https://github.com/kdl-org/kdl-test) under CI.

See the [documentation](https://impact-basin.github.io/KDLDocs.jl/) for more info.

## Quick start

```julia
using KDLDocs

doc = kdl"""
node example=#true {
    foo 1 2 3
    bar 4 5 6
}
"""

doc.node                 # the child node `node`
doc.node[:example]       # true
doc.node.foo[1]          # 1
arguments(doc.node.foo)  # [1, 2, 3]
```

A KDL node has arguments (positional values), properties (`key=value` pairs),
and children (nested nodes). Children read as fields, properties and arguments
by index, and `show` serialises any node back to KDL.

## Licence

MIT. See [LICENSE](LICENSE).
