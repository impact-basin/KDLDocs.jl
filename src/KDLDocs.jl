# ================================================
# █  ▄▀ █▀▀▀▄ █     █▀▀▀▄  ▄▄▄   ▄▄▄▄  ▄▄▄    ▀ █
# █▀▀▄  █   █ █     █   █ █   █ █     ▀▄▄▄    █ █
# █   █ █▄▄▄▀ █▄▄▄▄ █▄▄▄▀ ▀▄▄▄▀ ▀▄▄▄▄ ▄▄▄▄▀ ▄ █ █▄
# A parser for the KDL document language.   ▄▄█   
# ================================================
                                                  
module KDLDocs

"""
    KDLDocs

A parser for the [KDL document language](https://kdl.dev).
Parse with [`kdl`](@ref) (or the [`@kdl_str`](@ref) macro),
then navigate the result with `KDLNode`.

```julia
using KDLDocs

doc = kdl"node example=#true { foo 1 2 3 }"
doc[:node].example          # true
arguments(doc[:node, :foo]) # [1, 2, 3]
```
"""

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
