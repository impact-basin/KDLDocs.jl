using KDL


txt = """
    node foo123 = #true bar=34.56e7 { 
        baz abc = def {
            qux
        }
    }
"""
data = KDL.syntax(txt) |> KDL.semantics

g = KDL.g(txt)
KDL.kdl(g)
