# Tests for the KDLNode API (src/types.jl, src/io.jl) as documented in the
# README and exercised in test/scratch.jl.  Documents are parsed inline inside
# @test expressions so that a parse failure is reported per test.

@testset "API: KDLNode construction" begin
    # empty node
    n = KDLNode()
    @test n isa KDLNode
    @test isempty(arguments(n))
    @test isempty(properties(n))
    @test isempty(children(n))
    # children supplied as Pairs
    n = KDLNode(:a => KDLNode(), :b => KDLNode())
    @test node_names(n) == [:a, :b]
    @test n.a isa KDLNode
    # explicit arguments and properties
    n = KDLNode([1, 2], OrderedDict(:x => 1))
    @test arguments(n) == [1, 2]
    @test n[:x] == 1
end

# the README example document
const README_DOC = "node example=#true {\n    foo 1 2 3\n    bar 4 5 6 {\n        alpha\n        beta\n        gamma\n    }\n}"

@testset "API: getindex (children)" begin
    @test parse_doc(README_DOC).node isa KDLNode
    @test parse_doc(README_DOC).node.foo isa KDLNode
    @test parse_doc(README_DOC).node.bar isa KDLNode
    @test parse_doc(README_DOC).node.bar.alpha isa KDLNode
    @test parse_doc(README_DOC).node.bar.gamma isa KDLNode
    # propertynames lists the child names
    @test propertynames(parse_doc(README_DOC).node.bar) == (:alpha, :beta, :gamma)
    # integer indexing reaches arguments by position
    # a missing child is a FieldError, not missing
    @test_throws KDLDocs.FieldError parse_doc(README_DOC).node.nope
    @test parse_doc(README_DOC).node[:nope] === missing
    @test parse_doc(README_DOC).node.foo[1] == 1
    @test parse_doc(README_DOC).node.foo[3] == 3
end

@testset "API: setindex!" begin
    @test begin
        k = parse_doc("node { alpha }")
        k.node.beta = KDLNode()
        node_names(k.node) == [:alpha, :beta]
    end
    @test begin
        k = parse_doc("node { alpha }")
        k.node.beta = KDLNode()
        k.node.beta.delta = KDLNode()
        k.node.beta.delta isa KDLNode
    end
    @test begin
        k = parse_doc("node { alpha }")
        k.node.alpha = KDLNode()
        k.node.alpha isa KDLNode
    end
    @test begin
        k = parse_doc("node { alpha }")
        k.node.beta = KDLNode()
        k.node.beta.delta = KDLNode()
        k.node.beta.delta.eps = KDLNode()
        k.node.beta.delta.eps isa KDLNode
    end
    # integer set replaces an argument
    @test begin
        k = parse_doc("node 1 2 3")
        k.node[2] = 9
        arguments(k.node) == [1, 9, 3]
    end
end

@testset "API: properties" begin
    # property values are read and set through field syntax
    @test parse_doc("node example=#true").node[:example] === true
    @test parse_doc("node flag=#false").node[:flag] === false
    @test begin
        k = parse_doc("node example=#true")
        k.node[:example] = false
        k.node[:example] === false
    end
    # absent properties are missing; #false stays honest
    @test parse_doc("node flag=#false").node[:nope] === missing
    @test parse_doc("node flag=#false").node[:flag] !== missing
    # kebab and other non-identifier keys
    @test parse_doc("node my-key=1").node["my-key"] == 1
    @test properties(parse_doc("node \"my key\"=1").node)["my key"] == 1
    # propertynames drives tab completion, and lists the children
    @test propertynames(parse_doc("node { a; b }").node) == (:a, :b)
    @test haskey(parse_doc("node a=1 b=2").node, :a)
    # missing is not a KDL value
    @test_throws ArgumentError (parse_doc("node a=1").node[:b] = missing)
end

@testset "API: arguments" begin
    @test arguments(parse_doc("node 1 2 3 a b c").node) == [1, 2, 3, :a, :b, :c]
    @test arguments(parse_doc("node 1 1").node) == [1, 1]
    # membership uses isequal
    @test 1 in parse_doc("node 1 2 3").node
    @test :b in parse_doc("node a b c").node
    @test !(:z in parse_doc("node a b c").node)
    @test !(missing in parse_doc("node 1 2 3").node)
    # properties between arguments do not affect argument order
    @test arguments(parse_doc("foo 1 key=val 3").foo) == [1, 3]
    @test parse_doc("foo 1 key=val 3").foo[:key] === :val
    @test arguments(parse_doc("foo a=1 2 b=3 4").foo) == [2, 4]
    # push! appends an argument
    @test begin
        k = parse_doc("node 1")
        push!(k.node, 2)
        arguments(k.node) == [1, 2]
    end
end

@testset "API: haskey" begin
    @test haskey(parse_doc("node { child }\nother 1"), :node)
    @test haskey(parse_doc("node { child }\nother 1"), :other)
    @test !haskey(parse_doc("node { child }\nother 1"), :nope)
    @test haskey(parse_doc("node a=1").node, :a)
    # positional arguments are unnamed; membership is in
    @test 1 in parse_doc("other 1").other
    @test !haskey(parse_doc("other 1").other, 1)
end

@testset "API: empty!" begin
    @test begin
        k = parse_doc("node 1 2 { child }")
        empty!(k)
        isempty(arguments(k)) && isempty(properties(k)) && isempty(children(k))
    end
end

@testset "API: merge / merge!" begin
    @test argkeys(merge(parse_doc("foo 1"), parse_doc("bar 2")), :foo) == (1,)
    @test argkeys(merge(parse_doc("foo 1"), parse_doc("bar 2")), :bar) == (2,)
    @test begin
        m = merge!(parse_doc("foo 1"), parse_doc("bar 2"))
        haskey(m, :foo) && haskey(m, :bar)
    end
end

@testset "API: show round-trip" begin
    for s in [
        "foo 1 2 key=3",
        "node a=1 a=2",
        "foo #true #false #null",
        "foo 0x1A 0o17 0b101",
        "foo \"hi\" \"there\"",
        "foo 1.5 -2.5 1e10",
        "foo bar { baz }",
    ]
        @test parse_ok(sprint(show, parse_doc(s)))
        @test structeq(parse_doc(sprint(show, parse_doc(s))), parse_doc(s))
    end
end

@testset "API: kdl string macro" begin
    k = kdl"foo 1 2 key=3"
    @test k isa KDLNode
    @test argkeys(k, :foo) == (1, 2, :key)
    @test k.foo[:key] == 3
end

@testset "API: IO and files" begin
    mktempdir() do dir
        path = joinpath(dir, "doc.kdl")
        k = parse_doc("foo 1 2 key=3")
        write(path, sprint(show, k))
        @test structeq(open(path) do io
            kdl(io)
        end, k)
        # kdl(::IO) accepts any stream, not just IOStream
        @test structeq(kdl(IOBuffer(sprint(show, k))), k)
        @test structeq(KDLDocs.kdl_read(path), k)
        open(path, "w") do io
            write(io, k)
        end
        @test structeq(parse_doc(read(path, String)), k)
    end
end
