# Semantic actions for the KDL grammar, plus the value-processing helpers they
# rely on (string escapes, multi-line dedent, raw strings, numbers,
# identifiers).  Follows spec/kdl.txt section 3.

#
# Value helpers
#

const KDL_RESERVED_IDENTS = ("true", "false", "null", "inf", "-inf", "nan")

"""
    kdl_ident(s)

Validate the identifier text `s` (spec 3.10) and return it as a `Symbol`.
Reserved keywords (`true`, `false`, `null`, `inf`, `-inf`, `nan`) and
number-lookalike identifiers (`1foo`, `-1em`, `.1`, ...) are rejected.
"""
function kdl_ident(s)
    s in KDL_RESERVED_IDENTS &&
        throw(KDLParseError("`$s` is a reserved identifier; write it as a quoted or raw string"))
    c1 = first(s)
    if c1 in ('+', '-')
        if length(s) > 1
            c2 = s[2]
            if c2 == '.'
                # dotted form: sign '.' (identifier-char - digit)*  (e.g. `+.`, `-.md`)
                length(s) > 2 && isdigit(s[3]) &&
                    throw(KDLParseError("`$s` is not a valid identifier"))
            elseif isdigit(c2)
                throw(KDLParseError("`$s` is not a valid identifier"))
            end
        end
    elseif c1 == '.'
        length(s) > 1 && isdigit(s[2]) &&
            throw(KDLParseError("`$s` is not a valid identifier"))
    elseif isdigit(c1)
        throw(KDLParseError("`$s` is not a valid identifier"))
    end
    Symbol(s)
end

"""
    kdl_unicode_escape(s, i)

Interpret a `\\u{...}` escape whose `u` is at index `i` in `s`; return the
code point and the index after the closing brace.  Validates the hex digits
(1-6) and that the result is a Unicode scalar value (spec 3.11.1).
"""
function kdl_unicode_escape(s, i)
    j = nextind(s, i)
    j <= lastindex(s) && s[j] == '{' ||
        throw(KDLParseError("malformed unicode escape `\\u{...}`"))
    h = nextind(s, j)
    hstart = h
    while h <= lastindex(s) && isxdigit(s[h])
        h = nextind(s, h)
    end
    hexstr = s[hstart:prevind(s, h)]
    (1 <= length(hexstr) <= 6 && h <= lastindex(s) && s[h] == '}') ||
        throw(KDLParseError("malformed unicode escape `\\u{$(hexstr)…}`"))
    cp = parse(UInt32, hexstr, base = 16)
    (cp <= 0x10FFFF && !(0xD800 <= cp <= 0xDFFF)) ||
        throw(KDLParseError("`\\u{$(hexstr)}` is not a Unicode scalar value"))
    return Char(cp), nextind(s, h)
end

"""
    kdl_unescape(s)

Process the escape sequences of a string body `s` (spec 3.11.1): the
single-character escapes, `\\u{...}`, and escaped whitespace (backslash plus
one or more whitespace/newline characters, which is discarded).
"""
function kdl_unescape(s)
    out = IOBuffer()
    i = firstindex(s)
    n = lastindex(s)
    while i <= n
        c = s[i]
        if c == '\\'
            ni = nextind(s, i)
            ni > n && throw(KDLParseError("trailing backslash in string"))
            c2 = s[ni]
            if c2 == 'n'
                write(out, '\n')
            elseif c2 == 'r'
                write(out, '\r')
            elseif c2 == 't'
                write(out, '\t')
            elseif c2 == 'b'
                write(out, '\b')
            elseif c2 == 'f'
                write(out, '\f')
            elseif c2 == 's'
                write(out, ' ')
            elseif c2 == '\\'
                write(out, '\\')
            elseif c2 == '"'
                write(out, '"')
            elseif c2 == 'u'
                cp, i = kdl_unicode_escape(s, ni)
                write(out, cp)
                continue
            elseif is_unicode_space(c2) || is_newline(c2)
                # escaped whitespace: discard the backslash and all following whitespace
                i = nextind(s, ni)
                while i <= n && (is_unicode_space(s[i]) || is_newline(s[i]))
                    i = nextind(s, i)
                end
                continue
            else
                throw(KDLParseError("invalid escape sequence `\\$c2` in string"))
            end
            i = nextind(s, ni)
        else
            write(out, c)
            i = nextind(s, i)
        end
    end
    String(take!(out))
end

# strip the opening and closing quote from a single-line string match
kdl_string_body(v) = v[nextind(v, firstindex(v)):prevind(v, lastindex(v))]

"""
    kdl_resolve_ws_escapes(s)

Remove every escaped-whitespace sequence (`\\` followed by one or more
whitespace/newline characters) from `s`, leaving everything else untouched
(spec 3.12.3: this happens before dedenting and before other escapes).
A `\\\\` pair is an escape for a literal backslash and is left intact.
"""
function kdl_resolve_ws_escapes(s)
    out = IOBuffer()
    i = firstindex(s)
    n = lastindex(s)
    while i <= n
        c = s[i]
        if c == '\\'
            ni = nextind(s, i)
            if ni <= n && s[ni] == '\\'
                # `\\` is an escape for a literal backslash; keep both
                write(out, '\\', '\\')
                i = nextind(s, ni)
                continue
            elseif ni <= n && (is_unicode_space(s[ni]) || is_newline(s[ni]))
                i = nextind(s, ni)
                while i <= n && (is_unicode_space(s[i]) || is_newline(s[i]))
                    i = nextind(s, i)
                end
                continue
            end
        end
        write(out, c)
        i = nextind(s, i)
    end
    String(take!(out))
end

"""
    kdl_normalize_newlines(s)

Normalise every literal newline sequence in `s` to a single LF (spec 3.12.1).
"""
function kdl_normalize_newlines(s)
    s = replace(s, "\r\n" => "\n")
    replace(s, '\r' => '\n', '\u0085' => '\n', '\u000B' => '\n',
            '\u000C' => '\n', '\u2028' => '\n', '\u2029' => '\n')
end

"""
    kdl_dedent(body)

Apply the multi-line string rules (spec 3.12) to the body of a multi-line
string: the body starts with a newline, its final line must contain only
whitespace (which becomes the dedent prefix), whitespace-only lines become
empty lines, and every other line must start with exactly that prefix.  The
first and last newlines are omitted from the value.
"""
function kdl_dedent(body)
    lines = split(kdl_normalize_newlines(body), '\n')
    prefix = lines[end]
    all(is_unicode_space, prefix) ||
        throw(KDLParseError("multi-line string must end with a line of only whitespace"))
    out = String[]
    for i in 2:length(lines) - 1
        line = lines[i]
        if all(is_unicode_space, line)
            push!(out, "")
        else
            startswith(line, prefix) ||
                throw(KDLParseError("multi-line string line does not share the closing indentation"))
            push!(out, line[nextind(line, firstindex(line), length(prefix)):end])
        end
    end
    join(out, '\n')
end

"""
    kdl_multiline(s)

Build the value of a multi-line string from its full matched text (including
the `\"\"\"` delimiters): resolve whitespace escapes, dedent, then resolve the
remaining escapes (spec 3.12.3).
"""
function kdl_multiline(s)
    body = s[4:prevind(s, prevind(s, prevind(s, lastindex(s))))]
    kdl_unescape(kdl_dedent(kdl_resolve_ws_escapes(body)))
end

"""
    kdl_raw(s)

Build the value of a raw string from its full matched text (spec 3.13): no
escapes are processed; multi-line raw strings dedent like multi-line strings.
"""
function kdl_raw(s)
    i = firstindex(s)
    n = lastindex(s)
    h = 0
    while i <= n && s[i] == '#'
        h += 1
        i = nextind(s, i)
    end
    # `i` now points at the opening `"` (or the first `"` of `"""`)
    o2 = nextind(s, i)
    o3 = nextind(s, o2)
    if o3 <= n && s[o2] == '"' && s[o3] == '"'
        # multi-line raw string: closing is `"""` followed by h `#`s
        body_start = nextind(s, o3)
        j = body_start
        while true
            j2 = nextind(s, j)
            j3 = nextind(s, j2)
            if j3 <= n && s[j] == '"' && s[j2] == '"' && s[j3] == '"'
                k = nextind(s, j3)
                ok = true
                for _ in 1:h
                    (k <= n && s[k] == '#') || (ok = false; break)
                    k = nextind(s, k)
                end
                ok && break
            end
            j = nextind(s, j)
        end
        return kdl_dedent(s[body_start:prevind(s, j)])
    else
        # single-line raw string: closing is `"` followed by h `#`s
        body_start = nextind(s, i)
        j = body_start
        while true
            if s[j] == '"'
                k = nextind(s, j)
                ok = true
                for _ in 1:h
                    (k <= n && s[k] == '#') || (ok = false; break)
                    k = nextind(s, k)
                end
                ok && break
            end
            j = nextind(s, j)
        end
        return String(s[body_start:prevind(s, j)])
    end
end

"""
    kdl_float(s)

Parse a decimal string as a `Float64`, tolerating exponent overflow such as
`1.23E+1000` (which yields `Inf`) and underflow such as `1.23E-1000` (which
yields `0.0`).
"""
function kdl_float(s)
    try
        return parse(Float64, s)
    catch
        m = match(r"^([0-9.]+)[eE]([+-]?[0-9]+)$", s)
        m === nothing && rethrow()
        return parse(Float64, m[1]) * 10.0^parse(Int, m[2])
    end
end

"""
    kdl_radix(s, base)

Build an integer value from a hex/octal/binary number's full matched text
(sign, radix prefix and underscores handled).  Values that do not fit in an
`Int` fall back to `Float64`.
"""
function kdl_radix(s, base)
    sign = 1
    i = firstindex(s)
    if s[i] == '-'
        sign = -1
        i = nextind(s, i)
    elseif s[i] == '+'
        i = nextind(s, i)
    end
    digits = replace(s[nextind(s, i, 2):end], '_' => "")
    try
        return sign * parse(Int, digits, base = base)
    catch
        return sign * parse(Float64, "0x" * digits)
    end
end

"""
    kdl_decimal(s)

Build a number value from a decimal number's full matched text (spec 3.14):
integers stay `Int`, numbers with a fraction or a negative exponent become
`Float64`, and positive exponents keep integers integral.
"""
function kdl_decimal(s)
    sign = 1
    i = firstindex(s)
    if s[i] == '-'
        sign = -1
        s = s[nextind(s, i):end]
    elseif s[i] == '+'
        s = s[nextind(s, i):end]
    end
    s = replace(s, '_' => "")
    occursin('.', s) && return sign * kdl_float(s)
    m = match(r"^([0-9]+)[eE]([+-]?[0-9]+)$", s)
    if m !== nothing
        exp = parse(Int, m[2])
        if exp >= 0
            try
                return sign * parse(Int, m[1]) * 10^exp
            catch
                return sign * kdl_float(s)
            end
        end
        return sign * kdl_float(s)
    end
    sign * parse(Int, s)
end

# Treat an empty match view (which an empty `many` reports) as an empty list.
as_list(x::AbstractString) = Any[]
as_list(x) = x

"""
    build_entries(entries)

Split a node's entry list into `(arguments, properties)`.  Each entry is
`[separator, prop-or-arg]`, and entries whose separator was a slashdash are
dropped.  Positional arguments keep their order and duplicates; properties
are an `OrderedDict` with rightmost winning.
"""
function build_entries(entries)
    arguments  = Any[]
    properties = OrderedDict{Any,Any}()
    for entry in as_list(entries)
        sep, item = entry
        sep === :slashdash && continue
        if item isa Tuple
            key, val = item
            properties[key] = val
        else
            push!(arguments, item)
        end
    end
    (arguments, properties)
end

"""
    make_node(arguments, properties, body)

Construct a `KDLNode` from parsed arguments and properties, and a
`(children_dict, children_list)` body tuple (or `missing` when the node has
no children block).
"""
function make_node(arguments, properties, body)
    bd, bl = ismissing(body) ? (OrderedDict{Any,KDLNode}(), Pair{Any,KDLNode}[]) : body
    KDLNode(arguments, properties, bd, bl)
end

"""
    build_document(nodes)

Assemble a `KDLNode` document from the list of top-level node tuples
(slashdashed nodes are `nothing` and are skipped).  Each node tuple is
`(name, args, body, positional)`.
"""
function build_document(nodes)
    ret = KDLNode()
    for node in as_list(nodes)
        node === nothing && continue
        name, args, props, body = node
        child = make_node(args, props, body)
        getfield(ret, :body)[name] = child
        push!(getfield(ret, :children), name => child)
    end
    ret
end

#
# Semantic rules
#

semantics = @semantics :document m v ruletags=false begin
    :unicode_space       => nothing
    :newline             => nothing
    :multiline_comment   => nothing
    :singleline_comment  => nothing
    :ws                  => nothing
    :escline             => nothing
    :node_space          => nothing
    :line_space          => nothing
    :bom                 => nothing
    :version             => nothing
    :slashdash           => :slashdash
    :type                => nothing

    :ident               => kdl_ident(m.view)
    :singleline_string   => kdl_unescape(kdl_string_body(m.view))
    :multiline_string    => kdl_multiline(m.view)
    :raw_string          => kdl_raw(m.view)
    :string              => v[1]
    :sident              => v[1]

    :integer             => parse(Int, replace(m.view, "_" => ""))
    :decimal             => kdl_decimal(m.view)
    :hex                 => kdl_radix(m.view, 16)
    :octal               => kdl_radix(m.view, 8)
    :binary              => kdl_radix(m.view, 2)
    :keywordnumber       => m.view == "#inf" ? Inf : m.view == "#-inf" ? -Inf : NaN
    :keyword             => m.view == "#null" ? nothing : m.view == "#true"
    :number              => v[1]

    :value               => v[3][1]
    :prop                => (v[1], v[5])

    :node_entry          => v[1]
    :node_sep            => v[1]
    :slashdash_sep       => :slashdash

    :node_children       => begin
        ret  = OrderedDict{Any,KDLNode}()
        kids = Pair{Any,KDLNode}[]
        for node in as_list(v[2])
            node === nothing && continue
            name, args, props, body = node
            child = make_node(args, props, body)
            ret[name] = child
            push!(kids, name => child)
        end
        if v[3] isa AbstractVector && length(v[3]) == 1
            name, args, props, body = v[3][1]
            child = make_node(args, props, body)
            ret[name] = child
            push!(kids, name => child)
        end
        (ret, kids)
    end

    :children_part       => (length(v) == 3 && v[2] isa AbstractVector &&
                             length(v[2]) == 1 && v[2][1] isa AbstractVector &&
                             length(v[2][1]) == 2) ? v[2][1][2] : missing

    :node_head           => v[3]
    :node_base           => begin
        a, p = build_entries(v[2])
        (v[1], a, p, v[3])
    end
    :node_terminated     => v[1]
    :final_node          => v[1]

    :slashdash_node      => nothing
    :kdlnode             => v[1]

    :node_or_ws          => v[2]
    :final_node_or_ws    => v[2]
    :nodes               => begin
        isempty(v) && return Any[]
        list = as_list(v[1])
        if length(v) == 3 && v[2] isa AbstractVector && length(v[2]) == 1
            push!(list, v[2][1])
        end
        list
    end
    :document            => isempty(v) ? KDLNode() : build_document(v[3])
end
