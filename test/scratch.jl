using KDL


txt = """
    node foo123 = #true bar=34.56e7 fubar { 
        baz abc = def {
            qux 1 2 3
        }
    }
"""
data = KDL.syntax(txt) |> KDL.semantics

g = KDL.g(txt)
KDL.kdl(g)
