using KDL
using PrettyPrinting
import PikaParser as P

data = kdl"""
    node foo123 = #true bar=34.56e7 fubar { 
        baz abc = \"def\\n\" #==this is a raw string=# {
            qux 1 2 3
            \"node2\" 4 5 6
        }
    }
"""

data = KDL.syntax(txt) |> KDL.semantics

test = P.@semantics :kdl

tree = test(KDL.syntax(txt))

test(KDL.syntax(txt))

@time KDL.syntax(txt)
@benchmark KDL.syntax(txt)

g = KDL.g(txt)
KDL.kdl(g)
