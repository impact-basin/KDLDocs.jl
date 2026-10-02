# Valid documents: structure of documents, nodes, entries, children blocks,
# whitespace/comments, newlines, and disallowed code points.
# Spec sections 3.1-3.6 and 3.17-3.19.

@testset "3.1 Document" begin
    # a document is zero or more nodes
    @test parse_ok("")
    @test parse_ok("   ")
    @test parse_ok("\n\n")
    @test parse_ok("// just a comment\n")
    @test parse_ok("/* just a comment */")
    @test structeq(parse_doc(""), KDLNode())
    @test isempty(children(parse_doc("")))
    @test isempty(properties(parse_doc("")))
end

@testset "3.2 Node" begin
    # a bare node
    @test parse_doc("foo")[:foo] isa KDLNode
    @test structeq(parse_doc("foo")[:foo], KDLNode())
    # multiple nodes
    @test node_names(parse_doc("foo\nbar")) == [:foo, :bar]
    @test node_names(parse_doc("foo; bar")) == [:foo, :bar]
    @test node_names(parse_doc("foo\nbar; baz")) == [:foo, :bar, :baz]
    # trailing semicolon is a terminator, not a new node
    @test node_names(parse_doc("foo;")) == [:foo]
    # a node name may be a quoted string
    @test parse_doc("\"node2\" 4 5 6")["node2"] isa KDLNode
    @test argkeys(parse_doc("\"node2\" 4 5 6"), "node2") == (4, 5, 6)
    # ... or a raw string
    @test parse_doc("#\"my node\"# 1")["my node"] isa KDLNode
    @test argkeys(parse_doc("#\"my node\"# 1"), "my node") == (1,)
    # a node may be terminated by its parent's closing brace
    @test parse_doc("parent { child }")[:parent, :child] isa KDLNode
    # duplicate node names: last one wins (dict semantics)
    @test argkeys(parse_doc("foo 1\nfoo 2"), :foo) == (2,)
end

@testset "3.3 Line continuation" begin
    # spec 3.3.1: backslash + whitespace + newline joins lines
    @test argkeys(parse_doc("my-node 1 2 \\\n        3 4"), Symbol("my-node")) == (1, 2, 3, 4)
    # single-line comments are allowed after the backslash
    @test argkeys(parse_doc("my-node 1 2 \\  // comments are ok after \\\n        3 4"), Symbol("my-node")) == (1, 2, 3, 4)
    # multi-line comments are allowed after the backslash
    @test argkeys(parse_doc("my-node 1 2 \\ /* multi */ \n        3 4"), Symbol("my-node")) == (1, 2, 3, 4)
end

@testset "3.4 Property" begin
    @test parse_doc("node a=1 b=2")[:node].a == 1
    @test parse_doc("node a=1 b=2")[:node].b == 2
    # rightmost property with the same name wins (spec 3.4)
    @test parse_doc("node a=1 a=2")[:node].a == 2
    # property values of every kind
    @test parse_doc("node a=1.5 b=#true c=#null d=foo e=\"str\"")[:node].a ≈ 1.5
    @test parse_doc("node a=1.5 b=#true c=#null d=foo e=\"str\"")[:node].b === true
    @test parse_doc("node a=1.5 b=#true c=#null d=foo e=\"str\"")[:node].c === nothing
    @test parse_doc("node a=1.5 b=#true c=#null d=foo e=\"str\"")[:node].d === :foo
    @test parse_doc("node a=1.5 b=#true c=#null d=foo e=\"str\"")[:node].e == "str"
    # keys may be quoted strings
    @test properties(parse_doc("node \"my key\"=1")[:node])["my key"] == 1
    # keys may contain hyphens etc.
    @test parse_doc("node foo-bar=1")[:node].var"foo-bar" == 1
    # whitespace around '=' is allowed
    @test parse_doc("node a = 1")[:node].a == 1
    @test parse_doc("node a= 1 b =2")[:node].a == 1
    @test parse_doc("node a= 1 b =2")[:node].b == 2
end

@testset "3.5 Argument" begin
    # spec 3.5.1
    @test argkeys(parse_doc("my-node 1 2 3 a b c"), Symbol("my-node")) == (1, 2, 3, :a, :b, :c)
    # argument order is preserved; properties between arguments do not
    # affect argument ordering (spec 3.2, 3.5)
    @test arguments(parse_doc("foo 1 key=val 3")[:foo]) == [1, 3]
    @test parse_doc("foo 1 key=val 3")[:foo].key === :val
    # arguments and properties may be interleaved freely
    @test arguments(parse_doc("foo a=1 2 b=3 4")[:foo]) == [2, 4]
    @test collect(keys(properties(parse_doc("foo a=1 2 b=3 4")[:foo]))) == [:a, :b]
    # bare words after a node name are arguments, not nodes
    @test argkeys(parse_doc("foo bar baz"), :foo) == (:bar, :baz)
end

@testset "3.6 Children block" begin
    # spec 3.6.1
    @test node_names(parse_doc("parent {\n    child1\n    child2\n}")[:parent]) == [:child1, :child2]
    # single-line children block, terminated by semicolons
    @test node_names(parse_doc("parent { child1; child2 }")[:parent]) == [:child1, :child2]
    # an empty children block is legal
    @test isempty(children(parse_doc("parent { }")[:parent]))
    # deeply nested blocks
    @test parse_doc("a { b { c { d } } }")[:a, :b, :c, :d] isa KDLNode
    # children may carry arguments
    @test argkeys(parse_doc("parent { child 1 2 }"), :parent, :child) == (1, 2)
    # a node may have both entries and children
    @test argkeys(parse_doc("foo 1 2 { bar }"), :foo) == (1, 2)
    @test parse_doc("foo 1 2 { bar }")[:foo, :bar] isa KDLNode
    # trailing semicolon before the closing brace is fine
    @test node_names(parse_doc("parent { child1; child2; }")[:parent]) == [:child1, :child2]
end

@testset "3.17 Whitespace" begin
    # every unicode-space code point is valid node-space (spec 3.17 table)
    for ws in ['\t', ' ', '\u00A0', '\u1680', '\u2000', '\u2001', '\u2002',
               '\u2003', '\u2004', '\u2005', '\u2006', '\u2007', '\u2008',
               '\u2009', '\u200A', '\u202F', '\u205F', '\u3000']
        @test parse_ok("foo$(ws)1")
        @test arguments(parse_doc("foo$(ws)1")[:foo]) == [1]
    end
    # single-line comments (3.17.1)
    @test node_names(parse_doc("// leading comment\nfoo")) == [:foo]
    @test node_names(parse_doc("foo // trailing comment\nbar")) == [:foo, :bar]
    @test parse_ok("foo // comment at end of file")
    # multi-line comments (3.17.2)
    @test node_names(parse_doc("/* leading comment */ foo")) == [:foo]
    @test argkeys(parse_doc("foo /* inline */ 1"), :foo) == (1,)
    # multi-line comments may nest (3.17.2)
    @test node_names(parse_doc("/* a /* nested */ b */ foo")) == [:foo]
    # a multi-line comment may span lines; as whitespace it does not
    # terminate the node, so `bar` is an argument of `foo`
    @test argkeys(parse_doc("foo /* a\nb */ bar"), :foo) == (:bar,)
    # comments are whitespace between entries
    @test argkeys(parse_doc("foo 1 /* c */ 2"), :foo) == (1, 2)
end

@testset "3.17.3 Slashdash" begin
    # slashdash comments out a whole node
    @test node_names(parse_doc("/- foo\nbar")) == [:bar]
    @test node_names(parse_doc("/- foo 1 2 { x }\nbar")) == [:bar]
    # ... including across multiple lines (via line continuation)
    @test node_names(parse_doc("/- foo 1 \\\n  2 3\nbar")) == [:bar]
    # slashdash comments out an argument
    @test argkeys(parse_doc("foo 1 /- 2 3"), :foo) == (1, 3)
    # slashdash comments out a property
    @test collect(keys(properties(parse_doc("foo a=1 /- b=2 c=3")[:foo]))) == [:a, :c]
    # slashdash comments out a children block
    @test isempty(children(parse_doc("foo /- { bar }")[:foo]))
    # only children blocks may follow a slashdashed children block
    @test parse_doc("foo /- { bar } { baz }")[:foo, :baz] isa KDLNode
    # slashdash may be followed by whitespace, newlines, comments
    @test isempty(properties(parse_doc("foo /- \n /* c */ bar")[:foo]))
    # slashdash inside a children block
    @test node_names(parse_doc("foo { /- bar\n baz }")[:foo]) == [:baz]
    # slashdash of a property value is not allowed (3.17.3)
    @test parse_error("foo a=/- 1") isa Exception
    # only children blocks may follow a slashdashed children block
    @test parse_error("foo /- { bar } baz") isa Exception
end

@testset "3.18 Newlines" begin
    # CRLF, CR, LF, NEL, VT, FF, LS, PS all terminate nodes (spec 3.18)
    for nl in ["\r\n", "\r", "\n", "\u0085", "\u000B", "\u000C", "\u2028", "\u2029"]
        @test node_names(parse_doc("foo$(nl)bar")) == [:foo, :bar]
    end
    # CRLF counts as a single newline
    @test node_names(parse_doc("foo\r\n\r\nbar")) == [:foo, :bar]
    # newlines may separate nodes
    @test parse_ok("foo 1\nbar 2")
end

@testset "3.19 Disallowed literal code points" begin
    # these code points may not appear literally anywhere in a document
    for bad in ["\u0000", "\u0001", "\u0008", "\u000E", "\u001F", "\u007F",
                "\u200E", "\u200F", "\u202A", "\u202E", "\u2066", "\u2069",
                "\uFEFF"]
        @test parse_error("foo$(bad)") isa Exception
    end
    # ... nor inside strings
    for bad in ["\u0000", "\u0001", "\u0008", "\u000E", "\u001F", "\u007F",
                "\u200E", "\u200F", "\u202A", "\u202E", "\u2066", "\u2069"]
        @test parse_error("foo \"a$(bad)b\"") isa Exception
        @test parse_error("foo #\"a$(bad)b\"#") isa Exception
    end
    # the BOM is allowed only as the first code point of a document
    @test node_names(parse_doc("\uFEFFfoo")) == [:foo]
    @test parse_error("foo\uFEFF") isa Exception
end

@testset "Version marker" begin
    # a version marker at the start of the document parses as a comment
    @test node_names(parse_doc("/- kdl-version 2\nfoo")) == [:foo]
    @test node_names(parse_doc("\uFEFF/- kdl-version 1\nfoo")) == [:foo]
end
