# █  ▄▀ █▀▀▀▄ █     █▀▀▀▄  ▄▄▄   ▄▄▄▄  ▄▄▄    ▀ █
# █▀▀▄  █   █ █     █   █ █   █ █     ▀▄▄▄    █ █
# █   █ █▄▄▄▀ █▄▄▄▄ █▄▄▄▀ ▀▄▄▄▀ ▀▄▄▄▄ ▄▄▄▄▀ ▄ █ █▄
# A parser for the KDL document language.   ▄▄█   
                                                  
module KDL

export KDLNode, kdl, @kdl_str
public semantics, syntax

using Match
using DataStructures
using PrecompileTools: @compile_workload
using StyledStrings

import PikaParser as P

kdl(x::String) = x |> syntax |> semantics

include("types.jl")
include("io.jl")
include("syntax.jl")
include("semantics.jl")
#=include("precompile.jl")=#

end # module KDL
