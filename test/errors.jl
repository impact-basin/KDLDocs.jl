# Invalid documents: inputs that must fail to parse, organised by the spec
# rule they violate.  A parse may currently fail with any exception; see
# `parse_error` in helpers.jl.

@testset "Entries: malformed properties" begin
    @test parse_error("foo =") isa Exception        # no key
    @test parse_error("foo = 1") isa Exception
    @test parse_error("foo a=") isa Exception       # no value
    @test parse_error("foo a= ") isa Exception
    @test parse_error("foo a =") isa Exception
    @test parse_error("foo a==1") isa Exception
    @test parse_error("foo a=1=2") isa Exception
    @test parse_error("foo a=b c=") isa Exception
    @test parse_error("foo 1 = 2") isa Exception    # '=' where an arg should be
end

@testset "Entries: malformed type annotations" begin
    @test parse_error("foo ()") isa Exception       # empty type
    @test parse_error("foo (8)") isa Exception      # type must be a string
    @test parse_error("foo (u8)") isa Exception     # annotation with no value
    @test parse_error("foo a=(u8)") isa Exception
    @test parse_error("foo (u8)(u16)123") isa Exception
    @test parse_error("foo (u8") isa Exception      # unterminated
    @test parse_error("foo u8)") isa Exception      # stray ')'
end

@testset "Structure: braces, semicolons, terminators" begin
    @test parse_error("foo {") isa Exception        # unterminated children block
    @test parse_error("foo { bar") isa Exception
    @test parse_error("foo }") isa Exception        # stray '}'
    @test parse_error("}") isa Exception
    @test parse_error("{ foo }") isa Exception      # children block with no node
    @test parse_error("foo { ; }") isa Exception    # empty node inside a block
    @test parse_error("foo { bar;; }") isa Exception
    @test parse_error(";") isa Exception            # no node
    @test parse_error("foo ; ;") isa Exception
end

@testset "Structure: strings and string-ish tokens" begin
    @test parse_error("foo \"unterminated") isa Exception
    @test parse_error("foo \"a\nb\"") isa Exception # literal newline in quoted string
    @test parse_error("foo \"\"\"\nbar") isa Exception
    @test parse_error("foo #\"unterminated") isa Exception
    @test parse_error("foo #\"unterminated\"") isa Exception
    @test parse_error("foo ##\"a\"#") isa Exception
    @test parse_error("foo #") isa Exception        # bare '#'
    @test parse_error("foo #tru") isa Exception     # truncated keyword
    @test parse_error("foo \"a\\q\"") isa Exception # invalid escape
end

@testset "Structure: line continuation" begin
    # a continuation backslash must be followed by whitespace then a newline,
    # a single-line comment, or end of input
    @test parse_error("foo 1 \\ 2") isa Exception
    @test parse_error("foo 1 \\\t2") isa Exception
end

@testset "Values: identifier rules" begin
    @test parse_error("1foo") isa Exception
    @test parse_error("123abc") isa Exception
    @test parse_error("1.0v2") isa Exception
    @test parse_error("-1em") isa Exception
    @test parse_error("+1em") isa Exception
    @test parse_error(".1") isa Exception
    @test parse_error("foo\\bar") isa Exception     # '\' excluded from identifiers
    @test parse_error("foo/bar") isa Exception
    @test parse_error("foo(bar)") isa Exception     # '(' excluded
    @test parse_error("foo[bar]") isa Exception     # '[' excluded
    @test parse_error("foo#bar") isa Exception      # '#' excluded
    @test parse_error("foo=bar") isa Exception      # '=' excluded
end

@testset "Values: keyword identifiers" begin
    for kw in ["true", "false", "null", "inf", "-inf", "nan"]
        @test parse_error(kw) isa Exception
        @test parse_error("n $kw") isa Exception
        @test parse_error("n a=$kw") isa Exception
    end
end

@testset "Values: number rules" begin
    @test parse_error("n .5") isa Exception
    @test parse_error("n 1.") isa Exception
    @test parse_error("n 1e") isa Exception
    @test parse_error("n 1e+") isa Exception
    @test parse_error("n 0x") isa Exception
    @test parse_error("n 0x_1a") isa Exception
    @test parse_error("n 0o8") isa Exception
    @test parse_error("n 0b2") isa Exception
    @test parse_error("n 0x1.0") isa Exception
    @test parse_error("n 1x") isa Exception          # no space between tokens
    @test parse_error("n 1,2") isa Exception
    @test parse_error("n 1.2.3") isa Exception
    @test parse_error("n 1e10e10") isa Exception
end

@testset "Values: string rules" begin
    # disallowed literal code points anywhere in the document
    @test parse_error("foo\u0000") isa Exception
    @test parse_error("foo\u0001") isa Exception
    @test parse_error("foo\u007f") isa Exception
    @test parse_error("foo\u200e") isa Exception
    @test parse_error("foo\u202a") isa Exception
    @test parse_error("foo\u2066") isa Exception
    @test parse_error("foo\uFEFF") isa Exception     # BOM not at start
end

@testset "Values: type annotation placement" begin
    @test parse_error("foo (u8) (u16)") isa Exception  # second type has no value
    @test parse_error("foo a= (u8)") isa Exception
    @test parse_error("foo (u8)=") isa Exception
    @test parse_error("foo ( u8") isa Exception
end
