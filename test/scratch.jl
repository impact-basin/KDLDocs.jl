using KDLDocs

data = kdl"""node fubar { 
            qux 1 2 3
            \"node2\" 4 5 6
        }
    }
"""

data = KDLDocs.syntax(txt) |> KDLDocs.semantics

test = P.@semantics :kdl

tree = test(KDLDocs.syntax(txt))

test(KDLDocs.syntax(txt))

@time KDLDocs.syntax(txt)
@benchmark KDLDocs.syntax(txt)

g = KDLDocs.g(txt)
KDLDocs.kdl(g)


kdl"""package {
      name my_pkg
      version "1.2.3"
    
      dependencies {
        lodash optional=#true config=9.3
      }
    }
"""
