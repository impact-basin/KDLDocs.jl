# Shared helpers for the KDL test suite.
#
# The suite is written against the KDL 2.0 specification (spec/kdl.txt) and
# against the package's public API (see src/ and test/scratch.jl).  Many tests
# exercise behaviour the current implementation does not yet support; they are
# kept as plain `@test`s so that a test run doubles as a compliance report.

using KDLDocs
using DataStructures
using Test

export parse_doc, parse_error, parse_ok, structeq, val_eq, argkeys, node_names

"""
    parse_doc(s)

Parse the KDL document string `s` into a `KDLNode`.  Tests call this *inside*
`@test` expressions (e.g. `@test argkeys(parse_doc("n a"), :n) == (:a,)`), so
a parse failure surfaces as a per-test error and does not abort the enclosing
testset.
"""
parse_doc(s::AbstractString) = KDLDocs.kdl(String(s))

"""
    parse_error(s)

Return the exception raised while parsing `s`, or `nothing` if the parse
succeeds.  The package does not yet define a dedicated parse-error type, so
tests only assert that *some* error is raised for invalid input.
"""
function parse_error(s::AbstractString)
    try
        KDLDocs.kdl(String(s))
        return nothing
    catch e
        return e
    end
end

"""
    parse_ok(s)

Whether `s` parses successfully to a `KDLNode`.
"""
function parse_ok(s::AbstractString)
    try
        KDLDocs.kdl(String(s)) isa KDLNode
    catch
        return false
    end
end

# Treat an absent (`missing`) node field as an empty collection when comparing.
normdict(v::Missing) = OrderedDict{Any,Any}()
normdict(v::AbstractDict) = v
normdict(v::AbstractVector) = v
normdict(v::Tuple) = v

"""
    structeq(a, b)

Deep structural equality for parsed KDL data.  Handles `KDLNode`s,
`OrderedDict`s, `missing` (equal to an empty dict/list), vectors, tuples,
pairs, and scalar values compared with `isequal` (so `NaN` and `missing`
compare equal to themselves).
"""
structeq(a::KDLNode, b::KDLNode) = structeq(arguments(a), arguments(b)) &&
                                   structeq(properties(a), properties(b)) &&
                                   structeq(getfield(a, :body), getfield(b, :body)) &&
                                   structeq(children(a), children(b))
structeq(a::Missing, b::Missing) = true
structeq(a::Missing, b) = isempty(normdict(b))
structeq(a, b::Missing) = isempty(normdict(a))
structeq(a::AbstractDict, b::Missing) = isempty(a)
structeq(a::AbstractDict, b::AbstractDict) = _dict_eq(a, b)
structeq(a::AbstractDict, b) = false
structeq(a, b::AbstractDict) = false
structeq(a::AbstractVector, b::AbstractVector) =
    length(a) == length(b) && all(structeq(x, y) for (x, y) in zip(a, b))
structeq(a::Tuple, b::Tuple) =
    length(a) == length(b) && all(structeq(x, y) for (x, y) in zip(a, b))
structeq(a::Pair, b::Pair) = structeq(first(a), first(b)) && structeq(last(a), last(b))
structeq(a, b) = isequal(a, b)

function _dict_eq(a::AbstractDict, b::AbstractDict)
    length(a) == length(b) || return false
    for (k, v) in a
        haskey(b, k) || return false
        structeq(v, b[k]) || return false
    end
    return true
end

"""
    val_eq(got, expected)

Equality for parsed scalar values: exact `isequal` first (so `NaN` and
`missing` compare equal to themselves), falling back to `isapprox` for
numbers (float parsing need not be bit-exact).
"""
function val_eq(got, expected)
    isequal(got, expected) && return true
    got isa Number && expected isa Number && return isapprox(got, expected; nans=true)
    return false
end

"""
    argkeys(k, path...)

The positional arguments followed by the property keys of the node at
`path` in document `k`, as a `Tuple`.
"""
function argkeys(k::KDLNode, path...)
    node = foldl(getproperty, Symbol.(path); init = k)
    (arguments(node)..., keys(properties(node))...)
end

"""
    node_names(k)

The names of the child nodes of `k`, in document order.
"""
node_names(k::KDLNode) = [name for (name, _) in children(k)]
