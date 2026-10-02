# Values: identifier strings, quoted/raw/multi-line strings, numbers,
# booleans, null, and type annotations.
# Spec sections 3.7-3.16.

@testset "3.7/3.9 Values" begin
    # values may be strings, numbers, booleans, or null
    # (positional args are stored under bare keys, so the values must be distinct)
    @test argkeys(parse_doc("node foo \"bar\" 2 1.5 #true #false #null"), :node) ==
        (:foo, "bar", 2, 1.5, true, false, nothing)
end

@testset "3.10 Identifier strings" begin
    # plain identifiers
    @test parse_ok("foo")
    @test argkeys(parse_doc("n alpha beta"), :n) == (:alpha, :beta)
    # hyphens, dots, underscores and other punctuation are legal inside
    # identifiers (3.10.2 excludes only a small set)
    @test parse_ok("foo-bar")
    @test parse_ok("--this")
    @test parse_ok(".md")
    @test parse_ok("foo.bar")
    @test parse_ok("foo_bar")
    @test parse_ok("_12")
    @test parse_ok("foo-bar-baz")
    @test parse_ok("foo,bar")
    @test parse_ok("@foo")
    # keywords are only disallowed as exact identifiers
    @test parse_ok("truex")
    @test parse_ok("infinity")
    @test parse_ok("nanoid")
    @test parse_ok("nullish")
    @test parse_ok("falsehood")
    @test parse_ok("+inf")          # only `-inf` is a disallowed keyword ident
    @test parse_ok("+")             # a bare sign is a legal signed-ident
    @test parse_ok("-")
    @test parse_ok(".")             # a bare dot is a legal dotted-ident
    # unicode identifiers
    @test parse_ok("日本語")
    @test parse_ok("café")
    @test parse_ok("π")
    # number-lookalikes are not identifiers (3.10)
    @test parse_error("1foo") isa Exception
    @test parse_error("1.0v2") isa Exception
    @test parse_error("-1em") isa Exception
    @test parse_error("+1em") isa Exception
    @test parse_error(".1") isa Exception
    # disallowed keyword identifiers (3.10)
    @test parse_error("true") isa Exception
    @test parse_error("false") isa Exception
    @test parse_error("null") isa Exception
    @test parse_error("inf") isa Exception
    @test parse_error("-inf") isa Exception
    @test parse_error("nan") isa Exception
    # ... they are only reachable as quoted or raw strings
    @test parse_ok("\"true\"")
    @test parse_ok("#\"true\"#")
    # `\` and `/` are excluded from identifiers
    @test parse_error("foo\\bar") isa Exception
    @test parse_error("foo/bar") isa Exception
end

@testset "3.11 Quoted strings" begin
    # basic strings
    @test argkeys(parse_doc("n \"hello\""), :n) == ("hello",)
    @test argkeys(parse_doc("n \"\""), :n) == ("",)
    @test argkeys(parse_doc("n \"with spaces\""), :n) == ("with spaces",)
    @test argkeys(parse_doc("n \"café au lait\""), :n) == ("café au lait",)
    # escapes (3.11.1 table)
    @test argkeys(parse_doc("n \"a\\nb\""), :n) == ("a\nb",)
    @test argkeys(parse_doc("n \"a\\rb\""), :n) == ("a\rb",)
    @test argkeys(parse_doc("n \"a\\tb\""), :n) == ("a\tb",)
    @test argkeys(parse_doc("n \"a\\\\b\""), :n) == ("a\\b",)
    @test argkeys(parse_doc("n \"a\\\"b\""), :n) == ("a\"b",)
    @test argkeys(parse_doc("n \"a\\bb\""), :n) == ("a\bb",)
    @test argkeys(parse_doc("n \"a\\fb\""), :n) == ("a\fb",)
    @test argkeys(parse_doc("n \"a\\sb\""), :n) == ("a b",)      # \s is a space
    # unicode escapes (3.11.1)
    @test argkeys(parse_doc("n \"a\\u{41}b\""), :n) == ("aAb",)
    @test argkeys(parse_doc("n \"\\u{1F600}\""), :n) == ("\U0001F600",)
    @test argkeys(parse_doc("n \"\\u{0}\""), :n) == ("\0",)      # NUL via escape is fine
    # escaped whitespace (3.11.1.1): `\` + literal whitespace is discarded
    @test argkeys(parse_doc("n \"Hello \\    World\""), :n) == ("Hello World",)
    @test argkeys(parse_doc("n \"a\\\nb\""), :n) == ("ab",)
    @test argkeys(parse_doc("n \"a\\ \""), :n) == ("a",)   # \ + space before closing quote
    # literal newlines are not allowed in single-line strings
    @test parse_error("n \"a\nb\"") isa Exception
    # invalid escapes (3.11.1.2)
    @test parse_error("n \"a\\q\"") isa Exception
    @test parse_error("n \"a\\x\"") isa Exception
    # malformed unicode escapes
    @test parse_error("n \"\\u{}\"") isa Exception
    @test parse_error("n \"\\u{110000}\"") isa Exception   # above max scalar
    @test parse_error("n \"\\u{D800}\"") isa Exception     # surrogate
    @test parse_error("n \"\\u{1234567}\"") isa Exception  # 7 hex digits
    # disallowed literal code points may not appear in quoted strings (3.19)
    @test parse_error("n \"a\u0001b\"") isa Exception
    @test parse_error("n \"a\u007fb\"") isa Exception
    @test parse_error("n \"a\u200eb\"") isa Exception
end

@testset "3.12 Multi-line strings" begin
    # basic multi-line strings: first/last newline and dedent are stripped
    @test argkeys(parse_doc("n \"\"\"\nfoo\n\"\"\""), :n) == ("foo",)
    @test argkeys(parse_doc("n \"\"\"\n\"\"\""), :n) == ("",)
    @test argkeys(parse_doc("n \"\"\"\n  foo\n  bar\n  \"\"\""), :n) == ("foo\nbar",)
    # a string's final line sets the dedent prefix (3.12.2.1)
    @test argkeys(parse_doc("n \"\"\"\n        foo\n    This is the base indentation\n            bar\n    \"\"\""), :n) ==
        ("    foo\nThis is the base indentation\n        bar",)
    # a shorter final line dedents less (3.12.2.2)
    @test argkeys(parse_doc("n \"\"\"\n        foo\n    This is no longer on the left edge\n            bar\n  \"\"\""), :n) ==
        ("      foo\n  This is no longer on the left edge\n          bar",)
    # whitespace-only lines are always empty (3.12.2.3)
    @test argkeys(parse_doc("n \"\"\"\n    Indented a bit\n\n    A second indented paragraph.\n    \"\"\""), :n) ==
        ("Indented a bit\n\nA second indented paragraph.",)
    # literal newline sequences are normalised to LF (3.12.1)
    @test argkeys(parse_doc("n \"\"\"\r\nfoo\r\n\"\"\""), :n) == ("foo",)
    # escaped whitespace is resolved before dedenting (3.12.3)
    @test argkeys(parse_doc("n \"\"\"\n  foo \\\nbar\n  baz\n  \\   \"\"\""), :n) ==
        ("foo bar\nbaz",)
    # a multi-line string may be used as a node name
    @test parse_doc("\"\"\"\nmy name\n\"\"\" 1")["my name"] isa KDLNode
    # syntax errors (3.12.2.4)
    @test parse_error("n \"\"\"foo\"\"\"") isa Exception            # must start with newline
    @test parse_error("n \"\"\"\n  closing quote with non-whitespace prefix\"\"\"") isa Exception
    @test parse_error("n \"\"\"stuff\n  \"\"\"") isa Exception
    @test parse_error("n \"\"\"\nfoo\nbar\\\n\"\"\"") isa Exception  # escape eats the closing line
    @test parse_error("n \"\"\"\nfoo") isa Exception                  # unterminated
    @test parse_error("n \"\"\"\nfoo\nbar\"\"") isa Exception
end

@testset "3.13 Raw strings" begin
    # single-line raw strings (3.13.1)
    @test argkeys(parse_doc("n #\"foo\"#"), :n) == ("foo",)
    @test argkeys(parse_doc("n #\"\"#"), :n) == ("",)
    # escapes are NOT processed in raw strings
    @test argkeys(parse_doc("n #\"\\n\"#"), :n) == ("\\n",)
    # extra #'s extend the delimiter; the body may contain " and # freely
    @test argkeys(parse_doc("n ##\"a\"#b\"##"), :n) == ("a\"#b",)
    @test argkeys(parse_doc("n ##\"a\"##"), :n) == ("a",)
    @test argkeys(parse_doc("n ###\"a\"##b\"###"), :n) == ("a\"##b",)
    # raw strings may be node names
    @test parse_doc("#\"my node\"# 1")["my node"] isa KDLNode
    # multi-line raw strings dedent like multi-line strings
    @test argkeys(parse_doc("n #\"\"\"\nfoo\n\"\"\"#"), :n) == ("foo",)
    # spec 3.13.1: raw-multi-line example
    s = "raw-multi-line #\"\"\"\n    Here's a \"\"\"\n        multiline string\n        \"\"\"\n    without escapes.\n    \"\"\"#"
    @test argkeys(parse_doc(s), Symbol("raw-multi-line")) ==
        ("Here's a \"\"\"\n    multiline string\n    \"\"\"\nwithout escapes.",)
    # unterminated raw strings
    @test parse_error("n #\"foo\"") isa Exception
    @test parse_error("n #\"foo") isa Exception
    @test parse_error("n ##\"foo\"#") isa Exception
    # disallowed literal code points may not appear in raw strings (3.13)
    @test parse_error("n #\"a\u0001b\"#") isa Exception
end

@testset "3.14 Numbers" begin
    # integers and signs
    # (positional args are stored under bare keys, so the values must be distinct)
    @test argkeys(parse_doc("n 0 123 -123 +456"), :n) == (0, 123, -123, 456)
    @test argkeys(parse_doc("n -123 +123"), :n) == (-123, 123)
    # underscores between or after digits are ignored (3.14)
    @test argkeys(parse_doc("n 1_000"), :n) == (1000,)
    @test argkeys(parse_doc("n 1___2"), :n) == (12,)
    @test argkeys(parse_doc("n 12____"), :n) == (12,)
    @test argkeys(parse_doc("n 1_"), :n) == (1,)   # trailing underscore is legal
    @test argkeys(parse_doc("n 1_000_000"), :n) == (1000000,)
    # hexadecimal
    @test argkeys(parse_doc("n 0x0 0x1B 0xff 0xAB -0x1A +0x1A"), :n) == (0, 27, 255, 171, -26, 26)
    @test argkeys(parse_doc("n 0x1_0"), :n) == (16,)
    # octal
    @test argkeys(parse_doc("n 0o17 -0o17 0o7_7"), :n) == (15, -15, 63)
    # binary
    @test argkeys(parse_doc("n 0b101 0b1_0 -0b101"), :n) == (5, 2, -5)
    # decimals
    @test val_eq(parse_doc("n 1.5")[:n][1], 1.5)
    @test val_eq(parse_doc("n 0.1")[:n][1], 0.1)
    @test val_eq(parse_doc("n 123.456")[:n][1], 123.456)
    @test val_eq(parse_doc("n -2.5")[:n][1], -2.5)
    @test val_eq(parse_doc("n 0.0")[:n][1], 0.0)
    # exponents
    @test parse_doc("n 1e10")[:n][1] == 1e10
    @test parse_doc("n 1e-10")[:n][1] == 1e-10
    @test parse_doc("n 1E10")[:n][1] == 1e10
    @test parse_doc("n 1e+10")[:n][1] == 1e10
    @test argkeys(parse_doc("n 1e3 1e5"), :n) == (1000, 100000)
    @test val_eq(parse_doc("n 1.5e3")[:n][1], 1500.0)
    @test val_eq(parse_doc("n -2.5e-3")[:n][1], -0.0025)
    @test val_eq(parse_doc("n 1.5e-3")[:n][1], 0.0015)
    # keyword numbers (3.14.1)
    @test argkeys(parse_doc("n #inf #-inf"), :n) == (Inf, -Inf)
    @test isnan(parse_doc("n #nan")[:n][1])
    # invalid numbers
    @test parse_error("n .1") isa Exception
    @test parse_error("n 1.") isa Exception
    @test parse_error("n 1e") isa Exception
    @test parse_error("n 1e+") isa Exception
    @test parse_error("n 0x") isa Exception
    @test parse_error("n 0x_1a") isa Exception
    @test parse_error("n 0o8") isa Exception
    @test parse_error("n 0b2") isa Exception
    @test parse_error("n 0x1.0") isa Exception
    @test parse_error("n 1x") isa Exception
    @test parse_error("n 1,2") isa Exception
end

@testset "3.15 Booleans / 3.16 Null" begin
    # spec 3.15.1
    @test argkeys(parse_doc("my-node #true value=#false"), Symbol("my-node")) == (true, :value)
    @test parse_doc("my-node #true value=#false")[Symbol("my-node")].value === false
    # spec 3.16.1
    @test argkeys(parse_doc("my-node #null key=#null"), Symbol("my-node")) == (nothing, :key)
    @test parse_doc("my-node #null key=#null")[Symbol("my-node")].key === nothing
    # booleans and null as bare arguments
    @test argkeys(parse_doc("n #true #false #null"), :n) == (true, false, nothing)
    # `#` alone or truncated keywords are errors
    @test parse_error("n #") isa Exception
    @test parse_error("n #tru") isa Exception
    @test parse_error("n #nul") isa Exception
    @test parse_error("n #in") isa Exception
end

@testset "3.8 Type annotations" begin
    # on argument values; the annotation is a hint, the value is preserved
    @test argkeys(parse_doc("node (u8)123"), :node) == (123,)
    @test argkeys(parse_doc("node (u8) 123"), :node) == (123,)
    @test argkeys(parse_doc("node ( u8 )123"), :node) == (123,)
    @test val_eq(parse_doc("node (f32)1.5")[:node][1], 1.5)
    @test arguments(parse_doc("node (u8)123 (u16)456")[:node]) == [123, 456]
    # on property values
    @test parse_doc("node prop=(u8)123")[:node].prop == 123
    @test parse_doc("node prop=(regex).*")[:node].prop === Symbol(".*")
    # on node names (3.8.4)
    @test parse_doc("(published)date \"1970-01-01\"")[:date] isa KDLNode
    @test argkeys(parse_doc("(published)date \"1970-01-01\""), :date) == ("1970-01-01",)
    @test parse_doc("(contributor)person name=\"Foo McBar\"")[:person].name == "Foo McBar"
    @test parse_ok("( published )date 1")
end
