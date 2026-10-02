# Tests from the KDL reference test suite (test/testcases/), contributed by
# the user.  `valid/` cases are checked against their paired `.json` files
# (see corpus_helpers.jl for the comparison semantics); `invalid/` documents
# must fail to parse.

include("corpus_helpers.jl")

@testset "Reference corpus: valid documents" begin
    for f in corpus_files("valid")
        base = splitext(f)[1]
        ref = json_parse(read(corpus_path("valid", base * ".json"), String))
        doc = parse_doc(read(corpus_path("valid", f), String))
        @test doc_matches(doc, ref)
    end
end

@testset "Reference corpus: invalid documents" begin
    for f in corpus_files("invalid")
        @test parse_error(read(corpus_path("invalid", f), String)) isa Exception
    end
end
