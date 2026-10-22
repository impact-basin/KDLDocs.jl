# KDL query language.
#
# One selector AST is shared by three front ends:
#
#   - the `@query` macro, which reads a Julia expression;
#   - the PikaMacros query-string parser, used by `KDLQuery(str)`,
#     `query"..."`, ``query`...` `` and `query(doc, str)`;
#   - the evaluator below, which runs a compiled `KDLQuery` against a document.
#
# The parser's semantic fold produces a `KDLQuery` object (not a selector run
# against a document).  The `@query` and `@query_str` macros call that path
# during macro expansion and embed the resulting callable object as a literal,
# so literal queries are compiled once.
#
# The surface language is based on KQL, with the differences that Julia's
# syntax imposes (see the docstrings and docs/src/usage.md for the full list).

using MacroTools: @capture

"""
    KDLQueryError(msg[, pos])

Raised when a query cannot be parsed or violates a query-language rule.
`pos` is the byte offset into the query string, or `0` when the query was
written as a Julia expression.
"""
struct KDLQueryError <: Exception
    msg :: String
    pos :: Int
end
KDLQueryError(msg::AbstractString) = KDLQueryError(String(msg), 0)
Base.showerror(io::IO, e::KDLQueryError) =
    e.pos > 0 ? print(io, "KDL query error at byte ", e.pos, ": ", e.msg) :
                print(io, "KDL query error: ", e.msg)

# An accessor is the left-hand side of a matcher: val(), val(i), prop(key),
# name(), values(), props(), or a bare property key (prop shorthand).
struct Accessor
    kind :: Symbol   # :val, :prop, :name, :values, :props
    arg  :: Any      # Int for :val, key for :prop, nothing otherwise
end

struct Test
    accessor :: Accessor
    op       :: Symbol   # :exists, :eq, :ne, :gt, :ge, :lt, :le,
                         # :starts, :ends, :contains
    value    :: Any
end

# A filter is an optional name plus zero or more bracket tests.
struct Filter
    name  :: Union{Nothing, Symbol, AbstractString}
    tests :: Tuple{Vararg{Test}}
end

struct TopSelector end

const SelectorHead = Union{TopSelector, Filter}

# A chain is a head filter followed by (operator, filter) steps.  Operators
# are :> (child), :>> (descendant), :+ (next sibling) and :++ (later sibling).
struct Chain
    head  :: SelectorHead
    steps :: Tuple{Vararg{Tuple{Symbol, Filter}}}
end

struct UnionSelector
    branches :: Tuple{Vararg{Chain}}
end

"""
    KDLQuery

A compiled, callable KDL query.  Call it on a document, `q(doc)`, or pass it
to [`query`](@ref).  Build one from a string with `KDLQuery(str)` (parsed
when called), with the compile-time literals `query"..."` and
``query`...` ``, or from the expression dialect with the [`@query`](@ref)
macro.  The macro and literal forms embed the object in the compiled code, so
they are not reparsed on each use.
"""
struct KDLQuery
    root :: Union{Chain, UnionSelector}
end

KDLQuery(s::AbstractString) = parse_query(s)

#
# Query-string parser, written with PikaMacros so that the query grammar and
# the KDL grammar share one toolchain.  The string dialect accepts the same
# operators, matchers and Julia-style values as the expression dialect:
#
#   - `%=` (not `$=`) is ends-with;
#   - `type(...)` replaces `(tag)`/`()` and `tag(...)`;
#   - values are Julia values: `true`, `false`, `nothing`, `Inf`, `NaN`,
#     numbers, and `foo` (Symbol) vs `"foo"` (String);
#   - type annotations are rejected until KDLNode stores them.
#

is_query_ident_start(c::Char) = isletter(c) || c == '_'
is_query_ident_char(c::Char) =
    isletter(c) || isdigit(c) || c in ('_', '-', '.', '?')

"""
    kql_ident_scan(v)

PikaParser `scan` predicate for query identifiers: identifier characters up
to the next query metacharacter.  Returns the byte index of the last matched
character, or 0 when the view does not start an identifier.
"""
function kql_ident_scan(v)
    isempty(v) && return 0
    is_query_ident_start(v[firstindex(v)]) || return 0
    i = firstindex(v)
    n = lastindex(v)
    last = 0
    while i <= n && is_query_ident_char(v[i])
        last = i
        i = nextind(v, i)
    end
    last
end

# PikaParser scan for a double-quoted string with backslash escapes.  Returns
# the byte index of the closing quote.
function kql_string_scan(v)
    i = firstindex(v)
    n = lastindex(v)
    (i <= n && v[i] == '"') || return 0
    i = nextind(v, i)
    while i <= n
        c = v[i]
        if c == '\\'
            i = nextind(v, i)
            i <= n || return 0
        elseif c == '"'
            return i
        end
        i = nextind(v, i)
    end
    0
end

kql_string_text(v) =
    v[nextind(v, firstindex(v)):prevind(v, lastindex(v))]

function kql_unescape(s, pos)
    io = IOBuffer()
    i = firstindex(s)
    n = lastindex(s)
    while i <= n
        c = s[i]
        if c != '\\'
            write(io, c)
            i = nextind(s, i)
            continue
        end
        i = nextind(s, i)
        i <= n || throw(KDLQueryError("unterminated escape", pos))
        e = s[i]
        if e == 'n'
            write(io, '\n')
        elseif e == 'r'
            write(io, '\r')
        elseif e == 't'
            write(io, '\t')
        elseif e == 'b'
            write(io, '\b')
        elseif e == 'f'
            write(io, '\f')
        elseif e == 'v'
            write(io, '\v')
        elseif e == '0'
            write(io, '\0')
        elseif e == '\\' || e == '"' || e == '\''
            write(io, e)
        elseif e == 'u' || e == 'U'
            nhex = e == 'u' ? 4 : 8
            j = nextind(s, i)
            if j <= n && s[j] == '{'
                k = nextind(s, j)
                hstart = k
                while k <= n && s[k] != '}'
                    k = nextind(s, k)
                end
                k <= n || throw(KDLQueryError("unterminated unicode escape", pos))
                digits = s[hstart:prevind(s, k)]
                i = k
            else
                k = j
                for _ in 1:nhex
                    k <= n || throw(KDLQueryError("truncated unicode escape", pos))
                    k = nextind(s, k)
                end
                digits = s[j:prevind(s, k)]
                i = prevind(s, k)
            end
            cp = tryparse(UInt32, digits; base = 16)
            (cp === nothing || cp > 0x10ffff) &&
                throw(KDLQueryError("invalid unicode escape", pos))
            write(io, Char(cp))
        else
            throw(KDLQueryError("unknown escape `\\$e`", pos))
        end
        i = nextind(s, i)
    end
    String(take!(io))
end

function kql_number(s, pos)
    txt = replace(s, "_" => "")
    t = startswith(txt, "+") || startswith(txt, "-") ? txt[2:end] : txt
    radix = startswith(t, "0x") || startswith(t, "0X") ||
            startswith(t, "0o") || startswith(t, "0O") ||
            startswith(t, "0b") || startswith(t, "0B")
    if radix
        v = tryparse(Int, txt)
        v === nothing && throw(KDLQueryError("invalid number `$s`", pos))
        return v
    elseif occursin('.', t) || occursin('e', t) || occursin('E', t)
        v = tryparse(Float64, txt)
        v === nothing && throw(KDLQueryError("invalid number `$s`", pos))
        return v
    end
    v = tryparse(Int, txt)
    v === nothing || return v
    f = tryparse(Float64, txt)
    f === nothing && throw(KDLQueryError("invalid number `$s`", pos))
    f
end

# `many` reports an empty match as an empty string (or nothing); treat all
# three shapes as a list.
kql_list(x) = x === nothing ? Any[] : as_list(x)

function unsupported_type!(pos)
    throw(KDLQueryError("type annotations are not retained by KDLNode yet; " *
                        "the `type(...)` matcher is unavailable", pos))
end

query_syntax = @syntax :query begin

    :q_ws => r"\s+"

    :query => seq(many(:q_ws), :q_chain, many(:q_union_tail), many(:q_ws))

    :q_union_tail => seq(many(:q_ws), tokens("||"), many(:q_ws), :q_chain)

    :q_chain => seq(:q_filter, many(:q_step))

    :q_step => seq(many(:q_ws), :q_op, many(:q_ws), :q_filter)

    :q_op => first(tokens(">>"), tokens("++"), token('>'), token('+'))

    :q_filter => first(:q_top_filter, :q_type_filter, :q_name_filter,
                       :q_tests_filter)

    :q_top_filter => seq(tokens("top"), many(:q_ws), token('('),
                         many(:q_ws), token(')'))

    :q_type_filter => seq(:q_type, many(:q_matcher))

    :q_name_filter => seq(:q_name, many(:q_matcher))

    :q_tests_filter => some(:q_matcher)

    :q_name => first(:q_ident, :q_string)

    :q_type => seq(tokens("type"), many(:q_ws), token('('), many(:q_ws),
                   first(:q_name, epsilon), many(:q_ws), token(')'))

    :q_matcher => first(:q_matcher_full, :q_matcher_empty)

    :q_matcher_full => seq(token('['), many(:q_ws), :q_matcher_test,
                           many(:q_ws), token(']'))

    :q_matcher_test => first(:q_comparison, :q_accessor)

    :q_matcher_empty => seq(token('['), many(:q_ws), token(']'))

    :q_comparison => seq(:q_accessor, many(:q_ws), :q_cmp_op, many(:q_ws),
                         :q_value)

    :q_cmp_op => first(tokens("!="), tokens(">="), tokens("<="),
                       tokens("^="), tokens("%="), tokens("*="),
                       tokens("=="), tokens("\$="),
                       token('>'), token('<'), token('='))

    :q_accessor => first(:q_val_empty, :q_val_index, :q_prop_acc,
                         :q_name_acc, :q_type_acc, :q_tag_acc,
                         :q_values_acc, :q_props_acc, :q_shorthand_acc)

    :q_val_empty => seq(tokens("val"), many(:q_ws), token('('),
                        many(:q_ws), token(')'))

    :q_val_index => seq(tokens("val"), many(:q_ws), token('('),
                        many(:q_ws), :q_integer, many(:q_ws), token(')'))

    :q_prop_acc => seq(tokens("prop"), many(:q_ws), token('('),
                       many(:q_ws), :q_name, many(:q_ws), token(')'))

    :q_name_acc => seq(tokens("name"), many(:q_ws), token('('),
                       many(:q_ws), token(')'))

    :q_type_acc => seq(tokens("type"), many(:q_ws), token('('),
                       many(:q_ws), token(')'))

    :q_values_acc => seq(tokens("values"), many(:q_ws), token('('),
                         many(:q_ws), token(')'))

    :q_props_acc => seq(tokens("props"), many(:q_ws), token('('),
                        many(:q_ws), token(')'))

    :q_tag_acc => seq(tokens("tag"), many(:q_ws), token('('),
                      many(:q_ws), token(')'))

    :q_shorthand_acc => seq(:q_name)

    :q_value => first(:q_type_value, :q_number, :q_string, :q_keyword,
                      :q_ident)

    :q_type_value => seq(tokens("type"), many(:q_ws), token('('),
                         many(:q_ws), first(:q_name, epsilon),
                         many(:q_ws), token(')'))

    :q_keyword => first(tokens("true"), tokens("false"), tokens("nothing"),
                        tokens("Inf"), tokens("NaN"))

    :q_number => r"[+-]?(0[xX][0-9a-fA-F_]+|0[oO][0-7_]+|0[bB][01_]+|([0-9][0-9_]*(\.[0-9_]+)?([eE][+-]?[0-9_]+)?)|Inf|NaN)"

    :q_integer => r"[0-9][0-9_]*"

    :q_ident => scan(kql_ident_scan)

    :q_string => scan(kql_string_scan)

end

query_semantics = @semantics :query m v ruletags=false begin

    :query => begin
        branches = Chain[v[2]]
        append!(branches, kql_list(v[3]))
        root = length(branches) == 1 ? branches[1] : UnionSelector(Tuple(branches))
        KDLQuery(root)
    end

    :q_union_tail => v[4]

    :q_chain => begin
        steps = Tuple{Symbol, Filter}[]
        for step in kql_list(v[2])
            op, f = step
            f isa TopSelector &&
                throw(KDLQueryError("top() may only appear first in a selector", m.first))
            push!(steps, (op, f))
        end
        Chain(v[1], Tuple(steps))
    end

    :q_step => (v[2], v[4])

    :q_op => Symbol(m.view)

    :q_filter => v[1]

    :q_top_filter => TopSelector()

    :q_type_filter => unsupported_type!(m.first)

    :q_name_filter => Filter(v[1], Tuple(t for t in kql_list(v[2]) if t isa Test))

    :q_tests_filter => Filter(nothing, Tuple(t for t in v if t isa Test))

    :q_name => v[1]

    :q_type => nothing

    :q_matcher => v[1]

    :q_matcher_test => v[1]

    :q_matcher_full => begin
        t = v[3]
        t isa Test ? t : Test(t, :exists, nothing)
    end

    :q_matcher_empty => nothing

    :q_comparison => Test(v[1], v[3], v[5])

    :q_cmp_op => begin
        m.view == "!=" ? :ne :
        m.view == ">=" ? :ge :
        m.view == "<=" ? :le :
        m.view == "^=" ? :starts :
        m.view == "%=" ? :ends :
        m.view == "*=" ? :contains :
        m.view == "==" ? :eq :
        m.view == "\$=" ? throw(KDLQueryError("`\$=` is not available; use `%=` for ends-with", m.first)) :
        m.view == ">" ? :gt :
        m.view == "<" ? :lt : :eq
    end

    :q_accessor => v[1]

    :q_val_empty => Accessor(:val, 1)

    :q_val_index => Accessor(:val, v[5])

    :q_prop_acc => Accessor(:prop, v[5])

    :q_name_acc => Accessor(:name, nothing)

    :q_type_acc => unsupported_type!(m.first)

    :q_tag_acc => throw(KDLQueryError("`tag()` was renamed to `type()`", m.first))

    :q_values_acc => Accessor(:values, nothing)

    :q_props_acc => Accessor(:props, nothing)

    :q_shorthand_acc => Accessor(:prop, v[1])

    :q_value => v[1]

    :q_type_value => unsupported_type!(m.first)

    :q_keyword => begin
        m.view == "true" ? true :
        m.view == "false" ? false :
        m.view == "nothing" ? nothing :
        m.view == "Inf" ? Inf :
        m.view == "NaN" ? NaN : nothing
    end

    :q_number => kql_number(m.view, m.first)

    :q_integer => parse(Int, replace(m.view, "_" => ""))

    :q_ident => Symbol(m.view)

    :q_string => kql_unescape(kql_string_text(m.view), m.first)

end

"""
    parse_query(s)

Parse a query string into a callable [`KDLQuery`](@ref).  Not exported; use
`KDLQuery(s)`, `query"..."` or `query(doc, s)`.
"""
function parse_query(s::AbstractString)
    str = String(s)
    st = query_syntax(str)
    mid = PikaParser.find_match_at!(st, :query, 1)
    mid == 0 && throw(KDLQueryError("could not parse query", 1))
    last = st.matches[mid].last
    last == lastindex(str) ||
        throw(KDLQueryError("unexpected input: " *
                            repr(String(SubString(str, nextind(str, last)))),
                            nextind(str, last)))
    query_semantics(st)
end

#
# Expression dialect (`@query`): lower Julia syntax to the same selector AST.
#

function unwrap_block(ex::Expr)
    if ex.head === :block
        xs = Any[a for a in ex.args if !(a isa LineNumberNode)]
        length(xs) == 1 && return unwrap_block(xs[1])
    end
    ex
end
unwrap_block(ex) = ex

is_query_block(ex) = ex isa Expr && ex.head === :block

block_exprs(ex::Expr) = Any[a for a in ex.args if !(a isa LineNumberNode)]

const CHAIN_OPS = (:>, :>>, :+, :++)

# Return `(operands, operators)` in infix order, re-associating any grouping
# Julia imposed.  KQL chains are flat and left-associative.
function chain_parts(ex)
    ex = unwrap_block(ex)
    if ex isa Expr && ex.head === :comparison
        operands = Any[]
        ops = Symbol[]
        for (i, arg) in enumerate(ex.args)
            if isodd(i)
                o, oo = chain_parts(arg)
                append!(operands, o)
                append!(ops, oo)
            else
                (arg isa Symbol && arg in CHAIN_OPS) ||
                    throw(KDLQueryError("unsupported selector operator `$arg`"))
                push!(ops, arg)
            end
        end
        return (operands, ops)
    end
    matched = false
    op = nothing
    lhs = rhs = nothing
    if @capture(ex, a_ >> b_)
        op, lhs, rhs, matched = :>>, a, b, true
    elseif @capture(ex, a_ ++ b_)
        op, lhs, rhs, matched = :++, a, b, true
    elseif @capture(ex, a_ > b_)
        op, lhs, rhs, matched = :>, a, b, true
    elseif @capture(ex, a_ + b_)
        op, lhs, rhs, matched = :+, a, b, true
    end
    if matched
        lop, lo = chain_parts(lhs)
        rop, ro = chain_parts(rhs)
        return (vcat(lop, rop), vcat(lo, [op], ro))
    end
    (Any[ex], Symbol[])
end

function compile_union!(out, ex)
    ex = unwrap_block(ex)
    if ex isa Expr && ex.head === :||
        compile_union!(out, ex.args[1])
        compile_union!(out, ex.args[2])
    else
        push!(out, ex)
    end
end

function compile_selector(ex)
    branches = Any[]
    compile_union!(branches, ex)
    chains = Chain[compile_chain(b) for b in branches]
    length(chains) == 1 ? chains[1] : UnionSelector(Tuple(chains))
end

function compile_chain(ex)
    operands, ops = chain_parts(ex)
    head = compile_filter(operands[1])
    steps = Tuple{Symbol, Filter}[]
    for (k, op) in enumerate(ops)
        f = compile_filter(operands[k + 1])
        f isa TopSelector &&
            throw(KDLQueryError("top() may only appear first in a selector"))
        push!(steps, (op, f))
    end
    Chain(head, Tuple(steps))
end

function unsupported_type_expr()
    throw(KDLQueryError("type annotations are not retained by KDLNode yet; " *
                        "the `type(...)` matcher is unavailable"))
end

function compile_filter(ex)
    ex = unwrap_block(ex)
    if ex isa Symbol
        return Filter(ex, ())
    elseif ex isa AbstractString
        return Filter(String(ex), ())
    elseif ex isa Expr && ex.head === :call
        f = ex.args[1]
        if f === :top && length(ex.args) == 1
            return TopSelector()
        elseif f === :type
            unsupported_type_expr()
        end
        throw(KDLQueryError("expected a node name, `top()` or a matcher; " *
                            "got `$(sprint(show, ex))`"))
    elseif ex isa Expr && ex.head === :ref
        return compile_ref_filter(ex)
    elseif ex isa Expr && ex.head === :vect
        return Filter(nothing, compile_tests(ex.args))
    end
    throw(KDLQueryError("expected a node name, `top()` or a matcher; " *
                        "got `$(sprint(show, ex))`"))
end

function compile_ref_filter(ex)
    args = Any[]
    base = ex
    while base isa Expr && base.head === :ref
        append!(args, base.args[2:end])
        base = base.args[1]
    end
    if base isa Expr && base.head === :vect
        pre = compile_tests(base.args)
        return Filter(nothing, compile_tests(vcat(collect(pre), args)))
    end
    head = compile_filter(base)
    head isa TopSelector &&
        throw(KDLQueryError("top() cannot take matchers"))
    return Filter(head.name, compile_tests(vcat(collect(head.tests), args)))
end

function compile_tests(exs)
    tests = Test[]
    for ex in exs
        t = compile_test(ex)
        t === nothing || push!(tests, t)
    end
    Tuple(tests)
end

const CALL_TEST_OPS = Dict(Symbol("!=") => :ne, Symbol("==") => :eq,
                           Symbol(">") => :gt, Symbol(">=") => :ge,
                           Symbol("<") => :lt, Symbol("<=") => :le)
const HEAD_TEST_OPS = Dict(Symbol("^=") => :starts, Symbol("%=") => :ends,
                           Symbol("*=") => :contains)

function compile_test(ex)
    ex = unwrap_block(ex)
    if ex isa Expr && ex.head === :kw && length(ex.args) == 2
        return Test(compile_accessor(ex.args[1]), :eq, compile_value(ex.args[2]))
    elseif ex isa Expr && ex.head === :(=) && length(ex.args) == 2
        return Test(compile_accessor(ex.args[1]), :eq, compile_value(ex.args[2]))
    elseif ex isa Expr && haskey(HEAD_TEST_OPS, ex.head) && length(ex.args) == 2
        acc = compile_accessor(ex.args[1])
        acc.kind in (:values, :props) &&
            throw(KDLQueryError("`$(acc.kind)()` can only be tested for existence"))
        return Test(acc, HEAD_TEST_OPS[ex.head], compile_value(ex.args[2]))
    elseif ex isa Expr && ex.head === :call && length(ex.args) == 3 &&
           ex.args[1] isa Symbol && haskey(CALL_TEST_OPS, ex.args[1])
        acc = compile_accessor(ex.args[2])
        acc.kind in (:values, :props) &&
            throw(KDLQueryError("`$(acc.kind)()` can only be tested for existence"))
        return Test(acc, CALL_TEST_OPS[ex.args[1]], compile_value(ex.args[3]))
    end
    return Test(compile_accessor(ex), :exists, nothing)
end

function compile_accessor(ex)
    ex = unwrap_block(ex)
    if ex isa Symbol
        return Accessor(:prop, ex)
    elseif ex isa AbstractString
        return Accessor(:prop, String(ex))
    elseif ex isa Expr && ex.head === :call
        f = ex.args[1]
        args = ex.args[2:end]
        if f === :val
            if isempty(args)
                return Accessor(:val, 1)
            elseif length(args) == 1 && args[1] isa Integer
                return Accessor(:val, Int(args[1]))
            end
            throw(KDLQueryError("val() takes an integer index"))
        elseif f === :prop
            if length(args) == 1 && (args[1] isa Symbol || args[1] isa AbstractString)
                key = args[1] isa AbstractString ? String(args[1]) : args[1]
                return Accessor(:prop, key)
            end
            throw(KDLQueryError("prop() takes a property name"))
        elseif f === :name
            isempty(args) || throw(KDLQueryError("name() takes no arguments"))
            return Accessor(:name, nothing)
        elseif f === :type
            unsupported_type_expr()
        elseif f === :values
            isempty(args) || throw(KDLQueryError("values() takes no arguments"))
            return Accessor(:values, nothing)
        elseif f === :props
            isempty(args) || throw(KDLQueryError("props() takes no arguments"))
            return Accessor(:props, nothing)
        elseif f === :tag
            throw(KDLQueryError("`tag()` was renamed to `type()`"))
        end
        throw(KDLQueryError("unknown accessor `$(sprint(show, f))()`"))
    end
    throw(KDLQueryError("expected an accessor; got `$(sprint(show, ex))`"))
end

function compile_value(ex)
    ex = unwrap_block(ex)
    if ex isa Bool || ex isa Integer || ex isa AbstractFloat || ex isa AbstractString
        return ex
    elseif ex === nothing
        return nothing
    elseif ex isa Symbol
        ex === :nothing && return nothing
        ex === :Inf     && return Inf
        ex === :NaN     && return NaN
        return ex
    elseif @capture(ex, -x_)
        v = compile_value(x)
        v isa Number || throw(KDLQueryError("expected a number after `-`"))
        return -v
    elseif ex isa Expr && ex.head === :call && ex.args[1] === :type
        unsupported_type_expr()
    end
    throw(KDLQueryError("expected a query value; got `$(sprint(show, ex))`"))
end

function compile_query(ex)
    ex = unwrap_block(ex)
    KDLQuery(compile_selector(ex))
end

function query_macro_expr(args...)
    if length(args) == 1
        ex = args[1]
        if is_query_block(ex)
            qs = KDLQuery[compile_query(e) for e in block_exprs(ex)]
            return Expr(:tuple, map(QuoteNode, qs)...)
        end
        return QuoteNode(compile_query(ex))
    elseif length(args) == 2
        doc, ex = args
        if is_query_block(ex)
            qs = KDLQuery[compile_query(e) for e in block_exprs(ex)]
            d = gensym(:doc)
            calls = [Expr(:call, QuoteNode(q), d) for q in qs]
            body = Expr(:tuple, calls...)
            return esc(quote
                local $d = $doc
                $body
            end)
        end
        q = compile_query(ex)
        return :(($(QuoteNode(q)))($(esc(doc))))
    end
    throw(KDLQueryError("@query takes an optional document and a query " *
                        "expression, or a begin ... end block of queries"))
end

"""
    @query doc query
    @query query
    @query doc begin query1; query2; ... end
    @query begin query1; query2; ... end

Query a KDL document with a selector written as a Julia expression.  With a
document, the result is a `Vector{KDLNode}`; without one, the macro returns a
callable [`KDLQuery`](@ref).  A `begin ... end` block compiles each expression
and returns a tuple of results in the same shape.

The selector surface language follows KQL (`>` child, `>>` descendant,
`+` next sibling, `++` later sibling, `||` union), with Julia values:

```julia
@query doc m3 > l1
@query doc lola > bundle[url ^= "https://pds-geosciences"]
@query doc diviner > [] + []
q = @query top() > m3
q(doc)
m3, lola = @query doc begin
    top() > m3
    top() > lola
end
```

Differences from KQL: `%=` is ends-with (KQL's `\$=` cannot be written in
Julia), `type(...)` replaces `(tag)`/`tag(...)`, and values use Julia
literals (`true`, `false`, `nothing`, `Inf`, `NaN`, numbers, `foo` for a
Symbol, `"foo"` for a String).  Type-annotation matchers are rejected until
`KDLNode` retains annotations.
"""
macro query(args...)
    return query_macro_expr(args...)
end

"""
    query"selector"
    query`selector`

Parse a query string at macro-expansion time and return the resulting
callable [`KDLQuery`](@ref) literal, for use with `query(doc, ...)` or by
calling the result:

```julia
query"top() > m3"(doc)
```

Non-standard string literals do not interpolate, so `\$` is passed through to
the query parser rather than expanded; build dynamic queries with
`query(doc, str)` instead.
"""
macro query_str(s)
    QuoteNode(parse_query(String(s)))
end

"""
    query`selector`

Command-literal form of [`query"..."`](@ref).
"""
macro query_cmd(s)
    QuoteNode(parse_query(String(s)))
end

"""
    query(doc::KDLNode, selector)
    query(doc::KDLNode, q::KDLQuery)

Run a query against `doc`.  `selector` may be a query string or a compiled
[`KDLQuery`](@ref); the result is a `Vector{KDLNode}` in document order, with
duplicate matches removed by node identity.
"""
query(doc::KDLNode, s::AbstractString) = KDLQuery(s)(doc)
query(doc::KDLNode, q::KDLQuery) = q(doc)

#
# Evaluation.
#

struct QueryMatch
    parent :: Union{Nothing, KDLNode}
    node   :: KDLNode
end

function (q::KDLQuery)(doc::KDLNode)
    ordered(doc, run_selector(doc, q.root))
end

run_selector(doc::KDLNode, ch::Chain) = run_chain(doc, ch)

function run_selector(doc::KDLNode, u::UnionSelector)
    out = QueryMatch[]
    for branch in u.branches
        append!(out, run_chain(doc, branch))
    end
    out
end

function run_chain(doc::KDLNode, ch::Chain)
    if ch.head isa TopSelector
        isempty(ch.steps) && return top_matches(doc)
        # top() names the document itself: `top() > b` selects root children,
        # `top() >> b` searches the whole document.
        ms = QueryMatch[QueryMatch(nothing, doc)]
    else
        ms = filter_matches(all_matches(doc), ch.head)
    end
    for (op, f) in ch.steps
        ms = step_matches(op, ms, f)
    end
    ms
end

top_matches(doc::KDLNode) = QueryMatch[QueryMatch(doc, c) for c in children(doc)]

function all_matches(doc::KDLNode)
    out = QueryMatch[]
    function walk(n::KDLNode)
        for c in children(n)
            push!(out, QueryMatch(n, c))
            walk(c)
        end
    end
    walk(doc)
    out
end

function descendants(m::QueryMatch)
    out = QueryMatch[]
    function walk(n::KDLNode)
        for c in children(n)
            push!(out, QueryMatch(n, c))
            walk(c)
        end
    end
    walk(m.node)
    out
end

filter_matches(ms, f::Filter) = QueryMatch[m for m in ms if match_filter(m, f)]

function match_filter(m::QueryMatch, f::Filter)
    f.name === nothing || name_eq(m.node, f.name) || return false
    all(t -> match_test(m.node, t), f.tests)
end

function name_eq(node::KDLNode, key)
    n = nameof(node)
    n === nothing && return false
    string(n) == string(key)
end

function accessor_value(node::KDLNode, a::Accessor)
    if a.kind === :val
        args = arguments(node)
        1 <= a.arg <= length(args) ? args[a.arg] : missing
    elseif a.kind === :prop
        node[a.arg]
    elseif a.kind === :name
        n = nameof(node)
        n === nothing ? missing : string(n)
    end
end

function match_test(node::KDLNode, t::Test)
    a = t.accessor
    if a.kind === :values
        return t.op === :exists && !isempty(arguments(node))
    elseif a.kind === :props
        return t.op === :exists && !isempty(properties(node))
    end
    v = accessor_value(node, a)
    t.op === :exists && return v !== missing
    v === missing && return false
    if a.kind === :name
        w = t.value
        w isa Union{Symbol, AbstractString} || return false
        return compare(t.op, v, string(w))
    end
    compare(t.op, v, t.value)
end

function compare(op::Symbol, v, w)
    op === :eq && return typeof(v) === typeof(w) && isequal(v, w)
    op === :ne && return !(typeof(v) === typeof(w) && isequal(v, w))
    if op === :starts
        return v isa AbstractString && w isa AbstractString && startswith(v, w)
    elseif op === :ends
        return v isa AbstractString && w isa AbstractString && endswith(v, w)
    elseif op === :contains
        return v isa AbstractString && w isa AbstractString && occursin(w, v)
    elseif op in (:gt, :ge, :lt, :le)
        typeof(v) === typeof(w) || return false
        try
            op === :gt && return v > w
            op === :ge && return v >= w
            op === :lt && return v < w
            op === :le && return v <= w
        catch
            return false
        end
    end
    false
end

function step_matches(op::Symbol, ms::Vector{QueryMatch}, f::Filter)
    out = QueryMatch[]
    if op === :>
        for m in ms
            for c in children(m.node)
                cm = QueryMatch(m.node, c)
                match_filter(cm, f) && push!(out, cm)
            end
        end
    elseif op === :>>
        for m in ms
            for cm in descendants(m)
                match_filter(cm, f) && push!(out, cm)
            end
        end
    elseif op === :+
        for m in ms
            m.parent === nothing && continue
            sibs = children(m.parent)
            idx = findfirst(c -> c === m.node, sibs)
            (idx === nothing || idx == length(sibs)) && continue
            cm = QueryMatch(m.parent, sibs[idx + 1])
            match_filter(cm, f) && push!(out, cm)
        end
    elseif op === :++
        for m in ms
            m.parent === nothing && continue
            sibs = children(m.parent)
            idx = findfirst(c -> c === m.node, sibs)
            idx === nothing && continue
            for j in idx+1:length(sibs)
                cm = QueryMatch(m.parent, sibs[j])
                match_filter(cm, f) && push!(out, cm)
            end
        end
    end
    out
end

# Unique matches in document (preorder) order.
function ordered(doc::KDLNode, ms::Vector{QueryMatch})
    rank = IdDict{KDLNode, Int}()
    i = 0
    function walk(n::KDLNode)
        for c in children(n)
            i += 1
            rank[c] = i
            walk(c)
        end
    end
    walk(doc)
    seen = IdDict{KDLNode, Nothing}()
    out = KDLNode[]
    for m in ms
        haskey(seen, m.node) && continue
        seen[m.node] = nothing
        push!(out, m.node)
    end
    sort!(out; by = n -> rank[n])
    out
end
