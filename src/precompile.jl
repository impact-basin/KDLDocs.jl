# Precompilation workload for the parser.  Every document is an @kdl_str
# literal, so the parser runs at macro-expansion time, and the workload
# re-parses the printed form to keep kdl(::String) in the precompile trace.
# There is no file I/O here.
#
# Add a document whenever a new syntax rule lands, so the parse path and its
# error paths stay warm.

@compile_workload begin
    docs = (
        kdl"node example=#true { foo 1 2 3; bar 4 5 6 { alpha; beta; gamma } }",
        kdl"package { name my_pkg; version \"1.2.3\"; dependencies { lodash optional=#true config=9.3 } }",
        kdl"node 1 2 3 a b c key=#null other=0x1A pi=3.14 text=\"hi\" raw=#\"x\"# annotated=(u8)42",
        kdl"""
/- kdl-version 2
node a=1
node b=2; node c=3
""",
    )
    for doc in docs
        reparsed = kdl(sprint(show, doc))
        for node in children(reparsed)
            arguments(node)
            properties(node)
            children(node)
            propertynames(node)
        end
    end
    # Query path: the expression dialect compiles at macro-expansion time, the
    # string dialect parses at runtime.
    sample = kdl"node a=1 { child b=2 }"
    (@query top() > [])(sample)
    (@query node > child[name() = child])(sample)
    (query"node > child")(sample)
    query(sample, "node >> child[val() = 1]")
end
