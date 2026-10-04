# ================================================
# █  ▄▀ █▀▀▀▄ █     █▀▀▀▄  ▄▄▄   ▄▄▄▄  ▄▄▄    ▀ █
# █▀▀▄  █   █ █     █   █ █   █ █     ▀▄▄▄    █ █
# █   █ █▄▄▄▀ █▄▄▄▄ █▄▄▄▀ ▀▄▄▄▀ ▀▄▄▄▄ ▄▄▄▄▀ ▄ █ █▄
# A parser for the KDL document language.   ▄▄█   
# ================================================
                                                  
"""
    KDLDocs

A parser for the [KDL document language](https://kdl.dev).
Parse with [`kdl`](@ref) (or the [`@kdl_str`](@ref) macro),
then navigate the result with `KDLNode`:

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
"""
module KDLDocs


export KDLNode, KDLParseError, kdl, @kdl_str, arguments, properties, children

using Match
using DataStructures
using PrecompileTools: @compile_workload
using StyledStrings
using PikaMacros
import PikaParser

include("types.jl")
include("io.jl")
include("syntax.jl")
include("semantics.jl")
include("precompile.jl")

end # module KDLDocs
