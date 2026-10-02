"""
    kdl(x)

Parse `x` into a `KDLNode`, or throw `KDLParseError` if `x` is not valid.

`x` may be a `String` or an `IO`; the latter will be read in full.
"""
kdl(x::String) = kdl_pipeline(x)
kdl(x::IO) = kdl(read(x, String))

function kdl_pipeline(x::String)
    check_disallowed(x)
    st = syntax(x)
    mid = PikaParser.find_match_at!(st, :document, 1)
    mid == 0 && throw(KDLParseError("could not parse $(repr(x))"))
    last = st.matches[mid].last
    last == lastindex(x) ||
        throw(KDLParseError("unexpected input at position $(nextind(x, last)): $(repr(x[nextind(x, last):end]))"))
    return semantics(st)
end

# Serialise the arguments of a node: positional arguments in order, then
# properties.
function node_args(k::KDLNode)
    parts = Any[]
    append!(parts, [kdl_repr(v) * " " for v in arguments(k)])
    for (key, val) in properties(k)
        push!(parts, kdl_repr(key) * "=" * kdl_repr(val) * " ")
    end
    isempty(parts) ? "" : prod(parts)
end

# Serialise the children of a node in document order.
function node_body(k::KDLNode, top = false)
    kids = children(k)
    isempty(kids) && return styled""
    body = join([node_body(name, child) for (name, child) in kids], styled"\n")
    top && return body
    return "{" * indent("\n" * body) * "\n}\n"
end

node_body(k, v) = kdl_nodename(k) * " " * kdl_repr(v) * " "

function kdl_show(k::KDLNode, top=false)
    a = node_args(k)
    b = node_body(k, top)
    return a * b
end

"""
    show(io, k::KDLNode)

Serialise the node `k` back to KDL.
"""
Base.show(io::IO, k::KDLNode) = print(io, kdl_show(k, true))

"""
    write(io::IO, k::KDLNode)

Write the KDL serialisation of `k` to `io`.
"""
Base.write(io::IO, k::KDLNode) = write(io, kdl_show(k, true))

"""
    kdl_read(path)

Parse the KDL document stored in the file at `path`.
"""
kdl_read(s::String) = open(s, "r") do f
    read(f, String) |> kdl
end

"""
    @kdl_str "..."

Parse the KDL document in the string literal at macro-expansion time.  A
non-standard string literal passes Julia escape sequences through unchanged
apart from the escaped quote, so terminate nodes with a semicolon or use the
triple-quoted form for a multi-line document.
"""
macro kdl_str(s)
    k = kdl(s); quote $k end
end

is_unicode_space(c::Char) =
    c in ('\u0009', '\u0020', '\u00A0', '\u1680', '\u2000', '\u2001', '\u2002',
          '\u2003', '\u2004', '\u2005', '\u2006', '\u2007', '\u2008', '\u2009',
          '\u200A', '\u202F', '\u205F', '\u3000')

is_newline(c::Char) =
    c in ('\u000D', '\u000A', '\u0085', '\u000B', '\u000C', '\u2028', '\u2029')

function is_disallowed(c::Char)
    cp = UInt32(c)
    (0x0000 <= cp <= 0x0008) || (0x000E <= cp <= 0x001F) || cp == 0x007F ||
    (0x200E <= cp <= 0x200F) || (0x202A <= cp <= 0x202E) ||
    (0x2066 <= cp <= 0x2069) || cp == 0xFEFF
end
is_ident_char(c::Char) =
    !is_unicode_space(c) && !is_newline(c) && !is_disallowed(c) &&
    c ∉ ('\\', '/', '(', ')', '{', '}', '[', ']', '"', '#', '=', ';')

"""
    kdl_ident_scan(v)

PikaParser `scan` predicate for identifier strings: return the byte index of
the last matched identifier character in the view `v` (0 if none).  Byte
indices are required because the input may contain multi-byte characters.
"""
function kdl_ident_scan(v)
    i = firstindex(v)
    n = lastindex(v)
    last = 0
    while i <= n
        is_ident_char(v[i]) || break
        last = i
        i = nextind(v, i)
    end
    last
end

"""
    kdl_comment_scan(v)

PikaParser `scan` predicate for single-line comments: match `//` plus
everything up to the next newline or end of input (spec 3.17.1).  Returns
the byte index of the last matched character.
"""
function kdl_comment_scan(v)
    i = firstindex(v)
    n = lastindex(v)
    i + 1 <= n || return 0
    v[i] == '/' && v[i + 1] == '/' || return 0
    last = i + 1
    i = nextind(v, i, 2)
    while i <= n
        is_newline(v[i]) && break
        last = i
        i = nextind(v, i)
    end
    # include the terminating newline when there is one (spec 3.17.1)
    i <= n ? i : last
end

"""
    kdl_raw_scan(v)

PikaParser `scan` predicate for raw strings: match `#`-prefixed raw strings
(spec 3.13), single-line (`#"..."#`, `##"..."##`, ...) or multi-line
(`#` + triple-quote ... triple-quote + `#`).  Like the spec's cut point, the
first matching closing delimiter sequence ends the string.
"""
function kdl_raw_scan(v)
    i = firstindex(v)
    n = lastindex(v)
    # count leading `#`s (byte-safely)
    h = 0
    while i <= n && v[i] == '#'
        h += 1
        i = nextind(v, i)
    end
    h == 0 && return 0
    i <= n || return 0
    v[i] == '"' || return 0
    # multi-line raw string?
    ni = nextind(v, i)
    nni = nextind(v, ni)
    if nni <= n && v[ni] == '"' && v[nni] == '"'
        # first `"""` followed by h `#`s closes it
        j = nextind(v, nni)
        while j <= n
            jj = nextind(v, j)
            jjj = nextind(v, jj)
            if jjj <= n && v[j] == '"' && v[jj] == '"' && v[jjj] == '"'
                k = nextind(v, jjj)
                ok = true
                for _ in 1:h
                    (k <= n && v[k] == '#') || (ok = false; break)
                    k = nextind(v, k)
                end
                ok && return prevind(v, k)
            end
            j = nextind(v, j)
        end
        return 0
    else
        # single-line raw string: no newlines; first `"` followed by h `#`s closes it
        j = nextind(v, i)
        while j <= n
            c = v[j]
            is_newline(c) && return 0
            if c == '"'
                k = nextind(v, j)
                ok = true
                for _ in 1:h
                    (k <= n && v[k] == '#') || (ok = false; break)
                    k = nextind(v, k)
                end
                ok && return prevind(v, k)
            end
            j = nextind(v, j)
        end
        return 0
    end
end

"""
    check_disallowed(x)

Reject documents containing disallowed literal code points.
BOM (U+FEFF) is allowed only as the first code point.
"""
function check_disallowed(x)
    for (pos, c) in enumerate(x)
        if is_disallowed(c) && !(pos == 1 && c == '\uFEFF')
            throw(KDLParseError("disallowed code point U+$(uppercase(lpad(string(UInt32(c), base = 16), 4, '0'))) at position $pos"))
        end
    end
    x
end

"""
    kdl_format_string(s)

Serialise `s` as a single-line KDL string.  Quotes and backslashes are
escaped, the whitespace escapes use their short forms, and any code point the
spec forbids literally becomes a `\\u{...}` escape.
"""
function kdl_format_string(s)
    io = IOBuffer()
    write(io, '"')
    for c in s
        write(io, @match c begin
            '"'  => "\\\""
            '\\' => "\\\\"
            '\n' => "\\n"
            '\r' => "\\r"
            '\t' => "\\t"
            '\b' => "\\b"
            '\f' => "\\f"
            _    => c < ' ' || c == '\u007F' || is_disallowed(c) ?
                        "\\u{" * string(UInt32(c), base = 16) * "}" : string(c)
        end)
    end
    write(io, '"')
    String(take!(io))
end

kdl_format_number(s::Number) =
    isnan(s)         ? styled"#nan"  :
    s ==  Inf        ? styled"#inf"  :
    s == -Inf        ? styled"#-inf" : styled"$(repr(s))"

# A node name or argument key prints bare when its text is a legal bare
# identifier, and as a string otherwise.  Names parsed from a quoted or raw
# string arrive as a String, so those always print quoted.
function is_bare_ident(s::AbstractString)
    isempty(s) && return false
    kdl_ident_scan(s) == lastindex(s) || return false
    try
        kdl_ident(s)
        return true
    catch
        return false
    end
end

kdl_ident_repr(s::Symbol)         = is_bare_ident(string(s)) ? string(s) : kdl_format_string(string(s))
kdl_ident_repr(s::AbstractString) = kdl_format_string(s)

kdl_repr(k::KDLNode) = kdl_show(k, false)
kdl_repr(b::Bool)    = styled"{bright_blue:#$(repr(b))}"
kdl_repr(f::Number)  = styled"{bright_red:$(kdl_format_number(f))}"
kdl_repr(s::String)  = styled"{bright_red:$(kdl_format_string(s))}"
kdl_repr(s::Symbol)  = kdl_ident_repr(s)
kdl_repr(::Nothing)  = styled"{gray:#null}"

kdl_nodename(k) = styled"{cyan:$(kdl_ident_repr(k))}"
indent(s) = replace(s, styled"\n" => styled"\n\t")
