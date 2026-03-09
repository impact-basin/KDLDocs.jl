@compile_workload begin
    txt = """
        node foo123 = #true bar=34.56e7 fubar { 
            baz abc = \"def\\n\" #==this is a raw string=# {
                qux 1 2 3
                \"node2\" 4 5 6
            }
        }
    """
    data = KDL.syntax(txt) |> KDL.semantics

    data2 = kdl"""
        node foo123 = #true bar=34.56e7 fubar { 
            baz abc = \"def\\n\" #==this is a raw string=# {
                qux 1 2 3
                \"node2\" 4 5 6
            }
        }
    """

    kdl_show(data)
end
