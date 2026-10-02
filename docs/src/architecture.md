# Architecture

The parser is built in two layers on top of the
[PikaParser](https://github.com/PikaTools/PikaParser.jl) parsing library,
with the grammar and the semantic actions written using the
[PikaMacros](https://github.com/PikaTools/PikaMacros.jl) `syntax` /
`semantics` macros:

```
┌────────────────────────────────────────────────────────────┐
│ kdl(x)                                                     │
│   1. check_disallowed(x)      -- reject disallowed code pts│
│   2. st = syntax(x)           -- run the grammar           │
│   3. verify the match spans   -- or throw KDLParseError    │
│   4. semantics(st)            -- build the KDLNode tree    │
└────────────────────────────────────────────────────────────┘
```

## The pipeline

### 1. Input validation

`check_disallowed` scans the raw document and rejects the literal code points
that the specification forbids anywhere in a document (section 3.19 of the
spec): control characters, the delete character, direction-control characters,
and a BOM anywhere but as the very first code point.  Strings may still contain
them via `\u{...}` escapes, since those do not appear literally in the source.

### 2. The grammar (`syntax`)

`syntax.jl` defines the grammar with PikaMacros' `syntax` macro, closely
following the authoritative grammar in section 4 of the specification.  The
start rule is `:document`:

```
document  := bom? version? nodes
nodes     := (line-space* node)* line-space*
node      := node-head (node-sep entry)* children-part node-tail terminator
```

Key rules and the spec sections they implement:

  - `:unicode_space`, `:newline`: the exact code-point tables of spec 3.17
    and 3.18.
  - `:multiline_comment` / `:commented_block`: recursively matched so that
    `/* /* nested */ */` works (spec 3.17.2).
  - `:singleline_comment`: a `scan` predicate matching `//` through the
    next newline or end of input (spec 3.17.1).
  - `:escline`: the `\` line-continuation (spec 3.3), and `:node_tail`
    permits one whose continuation is end of input.
  - `:node_space` / `:line_space`: whitespace within a node (newlines must
    be escaped) versus whitespace where newlines are allowed.
  - `:slashdash`: handled as a node prefix (`:slashdash_node`), as an entry
    separator (`:node_sep`), and before children blocks (`:children_part`)
    (spec 3.17.3).
  - `:ident`: a `scan` predicate over identifier characters (spec 3.10);
    reserved keywords and number-lookalike identifiers are rejected
    semantically.
  - `:singleline_string`, `:multiline_string`, `:raw_string`: strings
    (spec 3.11 to 3.13); raw strings are matched with a `scan` that honours
    the spec's first-matching-closing-delimiter rule.
  - `:number`, `:decimal`, `:hex`, `:octal`, `:binary`: the number
    syntaxes (spec 3.14).

The grammar keeps structural rules free of epsilon-matching clauses:
PikaParser's epsilon fallback can otherwise invent zero-width matches at
arbitrary positions.  End-of-input handling is pushed to the top level, where
the span check in `kdl` rejects any leftover input.

### 3. The span check

PikaParser never reports failure directly: a parse either has no match for the
start rule or its best match does not span the whole input.  `kdl` checks
both and raises a `KDLParseError` with the position of the leftover input.

### 4. The semantic actions (`semantics`)

`semantics.jl` defines the semantic rules with the `semantics` macro and
implements all value processing in plain Julia helpers:

  - `kdl_ident` validates identifiers (spec 3.10): it rejects the reserved
    keywords `true`, `false`, `null`, `inf`, `-inf`, `nan` and
    number-lookalike forms such as `1foo`, `-1em` or `.1`, while allowing
    dotted and signed identifiers like `+.` or `--this`.
  - `kdl_unescape` / `kdl_unicode_escape` process quoted-string escapes
    (spec 3.11.1): `\n \r \t \\ \" \b \f \s` and `\u{...}`, plus escaped
    whitespace.
  - `kdl_multiline` / `kdl_resolve_ws_escapes` / `kdl_dedent` build
    multi-line strings (spec 3.12): whitespace escapes are resolved first, the
    string is dedented against the final line's whitespace prefix, and the
    remaining escapes are resolved.  Structural violations throw
    `KDLParseError`.
  - `kdl_raw` builds raw strings (spec 3.13); multi-line raw strings dedent
    like multi-line strings.
  - `kdl_radix` / `kdl_decimal` / `kdl_float` parse numbers (spec 3.14):
    underscores are stripped, signs and radix prefixes handled, and values that
    overflow an `Int` fall back to `Float64` (so `0xABCDEF...` and
    `1.23E+1000` still parse).
  - `build_entries`, `make_node` and `build_document` assemble the
    `KDLNode` tree.

Type annotations are parsed and discarded: the grammar accepts `(type)` before
a node name or value, and the semantic action drops it, so `(u8)123` and
`123` produce the same value.

## The data model

A [`KDLNode`](@ref) stores each of KDL's node parts directly:

| field        | contents                                                 |
|--------------|----------------------------------------------------------|
| `arguments`  | positional values in document order (duplicates kept)     |
| `properties` | `key => value` pairs (rightmost wins)                   |
| `body`       | children keyed by name (last occurrence wins)             |
| `children`   | `(name, node)` pairs in document order (duplicates)     |

[`arguments`](@ref), [`properties`](@ref) and [`children`](@ref) return
the collections.  `k[:name]` indexes a child and `k[1]` an argument;
`k.name` reads a property (`missing` when absent); `in` tests argument
membership; and `haskey` tests the keyed entries, properties and children.
The `body` dict is the name-keyed view of `children`, and the ordered lists
are what serialisation and the reference corpus tests use, so documents with
duplicate arguments or duplicate node names round-trip correctly.

`show` serialises a node back to KDL: arguments in order, then properties,
then children in document order.  The result of parsing a document round-trips
through `kdl`.

## Error handling

All parse failures raise [`KDLParseError`](@ref), with a message describing
the offending input.  A partially consumed document reports the position and
the remaining text.  The package does not report a full expected-here
diagnostic with a source span.
