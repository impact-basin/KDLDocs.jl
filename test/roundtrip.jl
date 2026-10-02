# Serialisation round-trip: show must emit KDL that parses back to the same
# document.  The reference corpus is the fixture set, so this also checks that
# show covers every construct the parser accepts.

@testset "Serialisation round-trip" begin
    for f in corpus_files("valid")
        doc = parse_doc(read(corpus_path("valid", f), String))
        out = sprint(show, doc)
        @test parse_ok(out)
        @test structeq(doc, parse_doc(out))
    end
end

@testset "Round-trip regressions" begin
    # byte-slicing: the last character of a quoted string is multibyte
    @test arguments(parse_doc("node \"é\"")[:node]) == ["é"]
    @test arguments(parse_doc("node \"日本語\"")[:node]) == ["日本語"]
    # identifiers that Julia's repr cannot round-trip
    for s in ["node +.", "\"\" arg", "node --", "node ?15"]
        @test structeq(parse_doc(s), parse_doc(sprint(show, parse_doc(s))))
    end
    # the printed form is stable after one pass
    for s in ["node +.", "\"\" arg", "node a=1", "node #\"x\"#"]
        once = sprint(show, parse_doc(s))
        @test sprint(show, parse_doc(once)) == once
    end
end
