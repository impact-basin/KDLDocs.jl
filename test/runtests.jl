# KDL test suite.
#
# Usage:
#     julia --project=. test/runtests.jl     # from the package root
#     (in a Julia session) pkg> test          # via Pkg.test()
#
# The suite covers the KDL 2.0 specification (spec/kdl.txt) and the package's
# public API (src/, README.md, test/scratch.jl).  Tests are written against
# the *specified* behaviour; tests that the current implementation does not
# yet satisfy are kept as plain `@test`s so that a test run doubles as a
# compliance report for the rework.

using Test

include("helpers.jl")

@testset "KDLDocs" begin
    include("api.jl")
    include("documents.jl")
    include("values.jl")
    include("errors.jl")
    include("spec_examples.jl")
    include("testcases.jl")
    include("roundtrip.jl")
end
