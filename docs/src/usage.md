# Usage

KDL is a node-oriented document language. A document is a sequence of nodes,
and each node has a name, then arguments and properties, then an optional block
of child nodes:

    node example=#true {
        foo 1 2 3
        bar 4 5 6
    }

Arguments are position-dependent values (`1 2 3`), properties are
position-independent assigned values (`example=#true`), and children are full
nodes. Values parse to Julia values: strings to `String`, numbers to `Int` or
`Float64`, `#true` and `#false` to `Bool`, and `#null` to `nothing`.

## Parsing

The entry point is [`kdl`](@ref). It reads a string, or a string literal:

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl("foo 1 2 key=3");

julia> doc = kdl"foo 1 2 key=3";

julia> doc isa KDLNode
true
```

... a file, or an open stream:

```jldoctest; setup = :(using KDLDocs)
julia> path = tempname();

julia> write(path, "foo 1 2 key=3");

julia> KDLDocs.kdl_read(path) isa KDLNode
true

julia> open(io -> kdl(io), path) isa KDLNode
true
```

Invalid documents raise a [`KDLParseError`](@ref):

```jldoctest; setup = :(using KDLDocs)
julia> try kdl("foo =") catch e; e isa KDLParseError end
true
```

## Children

Child nodes nest inside a node's braces, and they are stored by name. Reading a
name as a field returns the child; for duplicate names, the last occurrence:

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl"""
       package {
           name my_pkg
           dependencies {
               lodash optional=#true config=9.3
           }
       }
       """;

julia> doc.package isa KDLNode
true

julia> doc.package.dependencies.lodash[:optional]
true
```

A child whose name is not a Julia identifier is read with `var"..."`:

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl("\"my node\" 1");

julia> doc.var"my node" isa KDLNode
true
```

An absent child raises a `FieldError`, so test with [`haskey`](@ref) first:

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl"""
       package {
           name my_pkg
       }
       """;

julia> haskey(doc.package, :name)
true
```

[`propertynames`](@ref) lists the child names, and [`children`](@ref)
returns the ordered `(name, node)` pairs:

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl"""
       package {
           name my_pkg
       }
       """;

julia> propertynames(doc.package)
(:name,)

julia> [name for (name, _) in children(doc)] == [:package]
true
```

Assign a field to add or replace a child:

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl"""
       package {
           name my_pkg
       }
       """;

julia> doc.package.new_child = KDLNode();

julia> doc.package.new_child isa KDLNode
true
```

## Arguments and properties

Arguments are ordered and unnamed; properties are keyed. Arguments read by
integer index, and `in` tests membership:

```jldoctest; setup = :(using KDLDocs)
julia> node = kdl("foo 1 key=val 3").foo;

julia> arguments(node) == [1, 3]
true

julia> node[1]
1

julia> 1 in node
true

julia> :val in node
false
```

Argument order is significant, and duplicate arguments are preserved:

```jldoctest; setup = :(using KDLDocs)
julia> arguments(kdl("node arg arg").node) == [:arg, :arg]
true
```

Properties read by index. An absent property is `missing`, so a property set
to `#false` stays distinct from an absent one:

```jldoctest; setup = :(using KDLDocs)
julia> node = kdl("foo flag=#false").foo;

julia> node[:flag]
false

julia> node[:nope]
missing

julia> haskey(node, :flag)
true
```

Set a property by assignment:

```jldoctest; setup = :(using KDLDocs)
julia> node = kdl("foo flag=#false").foo;

julia> node[:flag] = true
true

julia> node[:flag]
true
```

`missing` is not a KDL value, so assigning it is an error:

```jldoctest; setup = :(using KDLDocs)
julia> node = kdl("foo flag=#false").foo;

julia> try node[:nope] = missing catch e; e isa ArgumentError end
true
```

Delete a property through `properties(node)`;

```jldoctest; setup = :(using KDLDocs)
julia> node = kdl("foo flag=#false").foo;

julia> delete!(properties(node), :flag);

julia> node[:flag]
missing
```

A key that is not a Julia identifier needs the string form. A `Symbol` and its
string form name the same property:

```jldoctest; setup = :(using KDLDocs)
julia> node = kdl("node my-key=1 \"my key\"=2").node;

julia> node["my-key"]
1

julia> node["my key"]
2
```

## Adding arguments

`push!` appends a positional argument, and integer assignment replaces one:

```jldoctest; setup = :(using KDLDocs)
julia> node = kdl("node 1 2").node;

julia> push!(node, 3);

julia> node[1] = 9;

julia> arguments(node) == [9, 2, 3]
true
```

## Duplicate node names

A document may hold sibling nodes with the same name. A field read returns the
last occurrence, while [`children`](@ref) keeps every occurrence in document
order:

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl"""
       node
       node
       """;

julia> length(children(doc))
2

julia> doc.node === last(children(doc))[2]
true
```

## Serialisation

`show` prints a node as KDL, and the output of a parsed document round-trips
through `kdl`:

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl"""
       foo 1 2 key=3 {
           bar
       }
       """;

julia> kdl(sprint(show, doc)) isa KDLNode
true
```

`write` writes the same serialisation to an `IO`:

```jldoctest; setup = :(using KDLDocs)
julia> doc = kdl("foo 1 2 key=3");

julia> path = tempname();

julia> open(io -> write(io, doc), path, "w");

julia> KDLDocs.kdl_read(path) isa KDLNode
true
```

## Merging

[`merge`](@ref) and [`merge!`](@ref) combine nodes:

```jldoctest; setup = :(using KDLDocs)
julia> a = kdl("foo 1");

julia> b = kdl("bar 2");

julia> m = merge(a, b);

julia> arguments(m.foo) == [1] && arguments(m.bar) == [2]
true
```
