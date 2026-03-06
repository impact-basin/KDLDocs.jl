using KDL


txt = """
    node foo123 = #true bar=34.56e7 fubar { 
        baz abc = \"def\\n\" #==this is a raw string=# {
            qux 1 2 3
            \"node2\" 4 5 6
        }
    }
"""
data = KDL.syntax(txt) |> KDL.semantics

g = KDL.g(txt)
KDL.kdl(g)

macro foo(bar)
    @show bar
    return quote 
        23
    end
end

s = match(r"#([=]+)((.|\n)*)(\1)#", "#==this is a raw string=#")

s = match(r"#([=]+)((.|\n)*)(\1)#", txt)

module C
    module A
        public foo
        foo = :bar
        macro foo()
            m = @__MODULE__
            @show __module__ m
            @show @eval(__module__, $m)
            @show @eval(__module__, $m.foo)
            return quote
                $m.foo
            end
        end
    end
end

import .C.A as B
