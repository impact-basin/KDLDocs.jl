# Precompilation workload for the parser.  Every document is an @kdl_str
# literal, so the parser runs at macro-expansion time, and the workload
# re-parses the printed form inside @compile_workload to keep kdl(::String)
# in the precompile trace.  There is no file I/O here.
#
# Add a document whenever a new syntax rule lands, so the parse path and its
# error paths stay warm.

@setup_workload begin
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

    @compile_workload begin
        for doc in docs
            reparsed = kdl(sprint(show, doc))
            for (_, node) in children(reparsed)
                arguments(node)
                properties(node)
                children(node)
                propertynames(node)
            end
        end
    end
end
