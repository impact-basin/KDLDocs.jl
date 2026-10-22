# KDLDocs.jl

A parser for the [KDL Document Language](https://kdl.dev), using
[PikaMacros](https://github.com/impact-basin/PikaMacros.jl) and
[PikaParser](https://github.com/LCSB-BioCore/PikaParser.jl).

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
nameof(doc.node)         # :node
doc.node[:example]       # true
doc.node.foo[1]          # 1
arguments(doc.node.foo)  # [1, 2, 3]
```

KDL nodes have names, arguments (positional values), properties
(`key=value` pairs), and children (nested nodes). Children are
accessed by fields, while properties and arguments are accessed
by indexing.

`show()` serialises KDL nodes back to the original KDL.

## Queries

There is a draft specification of a query language ("KQL") in the KDL
standards repo. A minor variant of this query language has been
implemented here via metaprogramming to make querying KDL docs easy.
Variance from the original specification is required because certain
symbols used in the query language (e.g. `$=`) result in illegal Julia
parses.

The `@query` macro selects nodes with the expression.
(`@query doc package >> name`).

You can also write the query as a string (e.g. via `query"..."`);
the resulting object is callable and will run the query
on the argumented KDL document.

## Licence

MIT. See [LICENSE](LICENSE).

## AI use.

I wrote most of this code myself. I used an LLM to fix up interfaces and ensure adherence to the KDL standard. I verified this code - and like it - and take as much responsibility for it as the terms of the LICENSE will allow.
