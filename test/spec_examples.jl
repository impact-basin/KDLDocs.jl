# Every worked example that appears in spec/kdl.txt, plus the example from
# test/scratch.jl, checked against the package API.

@testset "Spec 3.1.1" begin
    s = "foo {\n    bar\n}\nbaz"
    @test node_names(parse_doc(s)) == [:foo, :baz]
    @test parse_doc(s).foo.bar isa KDLNode
end

@testset "Spec 3.2.1" begin
    s = "foo 1 key=val 3 {\n    bar\n    (role)baz 1 2\n}"
    @test arguments(parse_doc(s).foo) == [1, 3]
    @test parse_doc(s).foo[:key] === :val
    @test parse_doc(s).foo.bar isa KDLNode
    @test argkeys(parse_doc(s), :foo, :baz) == (1, 2)
end

@testset "Spec 3.3.1" begin
    s = "my-node 1 2 \\  // comments are ok after \\\n        3 4    // This is the actual end of the Node."
    @test argkeys(parse_doc(s), Symbol("my-node")) == (1, 2, 3, 4)
end

@testset "Spec 3.4" begin
    @test parse_doc("node a=1 a=2").node[:a] == 2
end

@testset "Spec 3.5.1" begin
    @test argkeys(parse_doc("my-node 1 2 3 a b c"), Symbol("my-node")) == (1, 2, 3, :a, :b, :c)
end

@testset "Spec 3.6.1" begin
    @test node_names(parse_doc("parent {\n    child1\n    child2\n}").parent) == [:child1, :child2]
    @test node_names(parse_doc("parent { child1; child2 }").parent) == [:child1, :child2]
end

@testset "Spec 3.8.4" begin
    @test argkeys(parse_doc("node (u8)123"), :node) == (123,)
    @test parse_doc("node prop=(regex).*").node[:prop] === Symbol(".*")
    @test argkeys(parse_doc("(published)date \"1970-01-01\""), :date) == ("1970-01-01",)
    @test parse_doc("(contributor)person name=\"Foo McBar\"").person[:name] == "Foo McBar"
end

@testset "Spec 3.12.2.1 indented multi-line string" begin
    s = "multi-line \"\"\"\n        foo\n    This is the base indentation\n            bar\n    \"\"\""
    @test argkeys(parse_doc(s), Symbol("multi-line")) ==
        ("    foo\nThis is the base indentation\n        bar",)
end

@testset "Spec 3.12.2.2 shorter last-line indent" begin
    s = "multi-line \"\"\"\n        foo\n    This is no longer on the left edge\n            bar\n  \"\"\""
    @test argkeys(parse_doc(s), Symbol("multi-line")) ==
        ("      foo\n  This is no longer on the left edge\n          bar",)
end

@testset "Spec 3.12.2.3 empty lines" begin
    s = "multi-line \"\"\"\n    Indented a bit\n\n    A second indented paragraph.\n    \"\"\""
    @test argkeys(parse_doc(s), Symbol("multi-line")) ==
        ("Indented a bit\n\nA second indented paragraph.",)
end

@testset "Spec 3.13.1 raw strings" begin
    @test argkeys(parse_doc("just-escapes #\"\\n will be literal\"#"), Symbol("just-escapes")) ==
        ("\\n will be literal",)
    @test argkeys(parse_doc("quotes-and-escapes ##\"hello\\n\\r\\asd\"#world\"##"), Symbol("quotes-and-escapes")) ==
        ("hello\\n\\r\\asd\"#world",)
    s = "raw-multi-line #\"\"\"\n    Here's a \"\"\"\n        multiline string\n        \"\"\"\n    without escapes.\n    \"\"\"#"
    @test argkeys(parse_doc(s), Symbol("raw-multi-line")) ==
        ("Here's a \"\"\"\n    multiline string\n    \"\"\"\nwithout escapes.",)
end

@testset "Spec 3.14 keyword numbers" begin
    @test parse_doc("node #inf #-inf #nan").node[1] === Inf
    @test parse_doc("node #inf #-inf #nan").node[2] === -Inf
    @test isnan(parse_doc("node #inf #-inf #nan").node[3])
end

@testset "Spec 3.15.1 / 3.16.1" begin
    @test argkeys(parse_doc("my-node #true value=#false"), Symbol("my-node")) == (true, :value)
    @test parse_doc("my-node #true value=#false").var"my-node"[:value] === false
    @test argkeys(parse_doc("my-node #null key=#null"), Symbol("my-node")) == (nothing, :key)
    @test parse_doc("my-node #null key=#null").var"my-node"[:key] === nothing
end

@testset "scratch.jl package example" begin
    s = """
    package {
          name my_pkg
          version "1.2.3"
          dependencies {
            lodash optional=#true config=9.3
          }
        }
    """
    # `name my_pkg` and `version "1.2.3"` are child nodes whose bare words
    # are arguments; `dependencies` is a child node with its own children
    @test node_names(parse_doc(s).package) == [:name, :version, :dependencies]
    @test argkeys(parse_doc(s), :package, :name) == (:my_pkg,)
    @test argkeys(parse_doc(s), :package, :version) == ("1.2.3",)
    @test parse_doc(s).package.dependencies.lodash[:optional] === true
    @test parse_doc(s).package.dependencies.lodash[:config] == 9.3
    @test parse_doc(s).package.dependencies isa KDLNode
end
