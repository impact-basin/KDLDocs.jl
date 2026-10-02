# Helpers for the KDL reference corpus tests (test/testcases/).
#
# `valid/` contains KDL documents paired with `.json` files describing the
# expected parse result in the reference format:
#
#     [ { "type": <annotation|null>, "name": ..., "args": [ { "type": ...,
#       "value": { "type": "string"|"number"|"boolean"|"null", "value": ... } } ],
#       "props": { key: { ... } }, "children": [ ... ] } ]
#
# This package's data model (KDLNode with ordered args/body dicts) drops type
# annotations and represents values as Julia values, so the comparisons here
# ignore the annotation `type` fields and compare values by kind and content.

const CORPUS_DIR = joinpath(@__DIR__, "testcases")

corpus_files(kind) = sort(filter(f -> endswith(f, ".kdl"), readdir(joinpath(CORPUS_DIR, kind))))

"""
    corpus_path(kind, f)

Full path of a corpus file.
"""
corpus_path(kind, f) = joinpath(CORPUS_DIR, kind, f)

# --- minimal JSON parser (the reference files only need objects, arrays,
# strings, booleans and null; numbers appear only inside quoted strings) -----

function json_parse(s::AbstractString)
    chars = collect(s)
    val, i = json_value(chars, 1)
    skip_ws(chars, i) <= length(chars) && error("trailing JSON input")
    return val
end

function skip_ws(chars, i)
    while i <= length(chars) && chars[i] in (' ', '\t', '\n', '\r')
        i += 1
    end
    i
end

function json_value(chars, i)
    i = skip_ws(chars, i)
    i > length(chars) && error("unexpected end of JSON input")
    c = chars[i]
    c == '{' && return json_object(chars, i)
    c == '[' && return json_array(chars, i)
    c == '"' && return json_string(chars, i)
    c == 't' && (chars[i:i+3] == ['t', 'r', 'u', 'e'] || error("bad JSON"); return true, i + 4)
    c == 'f' && (chars[i:i+4] == ['f', 'a', 'l', 's', 'e'] || error("bad JSON"); return false, i + 5)
    c == 'n' && (chars[i:i+3] == ['n', 'u', 'l', 'l'] || error("bad JSON"); return nothing, i + 4)
    error("unexpected JSON character `$c`")
end

function json_object(chars, i)
    obj = Dict{String, Any}()
    i = skip_ws(chars, i + 1)
    chars[i] == '}' && return obj, i + 1
    while true
        key, i = json_string(chars, i)
        i = skip_ws(chars, i)
        chars[i] == ':' || error("expected `:` in JSON object")
        val, i = json_value(chars, i + 1)
        obj[key] = val
        i = skip_ws(chars, i)
        chars[i] == ',' && (i = skip_ws(chars, i + 1); continue)
        chars[i] == '}' && return obj, i + 1
        error("expected `,` or `}` in JSON object")
    end
end

function json_array(chars, i)
    arr = Any[]
    i = skip_ws(chars, i + 1)
    chars[i] == ']' && return arr, i + 1
    while true
        val, i = json_value(chars, i)
        push!(arr, val)
        i = skip_ws(chars, i)
        chars[i] == ',' && (i = skip_ws(chars, i + 1); continue)
        chars[i] == ']' && return arr, i + 1
        error("expected `,` or `]` in JSON array")
    end
end

function json_string(chars, i)
    chars[i] == '"' || error("expected string")
    out = IOBuffer()
    i += 1
    while i <= length(chars)
        c = chars[i]
        if c == '"'
            return String(take!(out)), i + 1
        elseif c == '\\'
            i += 1
            e = chars[i]
            if e == '"'; write(out, '"')
            elseif e == '\\'; write(out, '\\')
            elseif e == '/'; write(out, '/')
            elseif e == 'b'; write(out, '\b')
            elseif e == 'f'; write(out, '\f')
            elseif e == 'n'; write(out, '\n')
            elseif e == 'r'; write(out, '\r')
            elseif e == 't'; write(out, '\t')
            elseif e == 'u'
                write(out, Char(parse(UInt32, String(chars[i+1:i+4]), base = 16)))
                i += 4
            else
                error("bad JSON escape")
            end
        else
            write(out, c)
        end
        i += 1
    end
    error("unterminated JSON string")
end

# --- comparison helpers -----------------------------------------------------

"""
    value_matches(myval, ref)

Whether the parsed Julia value `myval` corresponds to the reference JSON value
dictionary `ref` (whose `type` annotation field is ignored).
"""
function value_matches(myval, ref)
    ref isa AbstractDict || return false
    t = ref["type"]
    if t == "null"
        return myval === nothing
    elseif t == "boolean"
        return myval isa Bool && (myval ? "true" : "false") == ref["value"]
    elseif t == "string"
        return myval isa Union{Symbol, AbstractString} && string(myval) == ref["value"]
    elseif t == "number"
        myval isa Number || return false
        rv = ref["value"]
        rn = rv == "inf" ? Inf : rv == "-inf" ? -Inf : rv == "nan" ? NaN : tryparse(Float64, rv)
        if rn === nothing
            # the reference value overflows/underflows Float64; only a matching
            # overflow (Inf) or underflow (0.0) of our own parse counts
            big = parse(BigFloat, rv)
            return (isinf(float(myval)) && abs(big) > floatmax(Float64)) ||
                   (myval == 0 && abs(big) < 1e-300)
        end
        return isnan(rn) ? isnan(float(myval)) : (isequal(myval, rn) || isapprox(float(myval), rn))
    end
    return false
end

name_matches(myname, refname) = (myname isa Symbol ? String(myname) : myname) == refname

"""
    node_matches(k, ref)

Whether the parsed node `k` matches the reference node dictionary `ref`
(ignoring annotation types).  The node's own name is compared by the caller,
since KDLNode stores names as dict keys in the parent.  Positional arguments
and children come from the ordered lists that preserve duplicates; properties
come from the argument dict.
"""
function node_matches(k::KDLNode, ref)
    ref isa AbstractDict || return false
    # positional arguments, in order (duplicates preserved)
    myargs = arguments(k)
    refargs = ref["args"]
    length(myargs) == length(refargs) || return false
    for (v, r) in zip(myargs, refargs)
        value_matches(v, r["value"]) || return false
    end
    # properties
    myprops = properties(k)
    refprops = ref["props"]
    length(myprops) == length(refprops) || return false
    for (key, v) in myprops
        haskey(refprops, string(key)) || return false
        value_matches(v, refprops[string(key)]["value"]) || return false
    end
    # children, in document order (duplicate names preserved)
    mychildren = children(k)
    refchildren = ref["children"]
    length(mychildren) == length(refchildren) || return false
    for ((cname, c), r) in zip(mychildren, refchildren)
        (name_matches(cname, r["name"]) && node_matches(c, r)) || return false
    end
    return true
end

"""
    doc_matches(k, ref)

Whether the parsed document `k` matches the reference JSON document (an array
of node dictionaries).  Top-level nodes come from the ordered children list,
so duplicate node names are preserved.
"""
function doc_matches(k::KDLNode, ref)
    ref isa AbstractVector || return false
    mynodes = children(k)
    length(mynodes) == length(ref) || return false
    for ((name, child), r) in zip(mynodes, ref)
        (name_matches(name, r["name"]) && node_matches(child, r)) || return false
    end
    return true
end
