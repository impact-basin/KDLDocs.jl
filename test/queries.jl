# Query-language (`@query`, `KDLQuery`, `query"..."`) tests.
#
# The surface language is based on KQL, but it is Julia's syntax (for the
# macro) or a Julia-flavoured string dialect.  Deliberate differences from the
# upstream KQL spec:
#
#   - `%=` is ends-with; KQL's `$=` is not a Julia operator;
#   - `type(...)` replaces `(tag)` / `tag(...)`, and is rejected for now
#     because KDLNode does not retain type annotations;
#   - values are Julia values: `true`, `false`, `nothing`, `Inf`, `NaN`,
#     numbers, `foo` (Symbol), `"foo"` (String).
#
# The expression dialect applies Julia's grouping first, then flattens the
# selector chain left-associatively (KQL has no grouping), so `a > b >> c`
# means `(a > b) >> c` even though Julia parses it as `a > (b >> c)`.

using KDLDocs
using Test

const PDS = kdl(read(joinpath(@__DIR__, "testcases", "query", "pds.kdl"), String))
# const PDS = kdl(read("test/testcases/query/pds.kdl") |> String)

# m3 = only(@query PDS m3)
# lola = only(@query PDS lola)
#
# urls = @query PDS lola >> []
#
# @query m3 default >> []
#
# @query PDS lola 

names(ms) = nameof.(ms)

const ROOTS = [:m3, :ovirs, :lola, :naif, :lamp, :diviner]

@testset "Queries" begin

    @testset "top() and direct children" begin
        @test names(@query PDS top()) == ROOTS
        @test names(@query PDS top() > []) == ROOTS
        @test isempty(@query PDS top() > default)
        @test names(@query PDS top() > m3 > []) == [:l1, :l2, :default]

        # A leading filter without top() is a deep search.
        @test names(@query PDS m3 > []) == [:l1, :l2, :default]
    end

    @testset "descendants" begin
        @test names(@query PDS m3 >> l1) == [:l1]
        @test only(@query PDS m3 >> l1)[:url] ==
              "https://planetarydata.jpl.nasa.gov/img/data/m3/CH1M3_0003/"

        @test names(@query PDS lola >> bundle > []) == [:ldam, :ldec, :ldem, :ldrm]
        @test length(@query PDS lola >> []) == 28
        @test names(@query PDS default) == fill(:default, 5)
        @test names(@query PDS lola >> resolution > []) ==
              [:res_4, :res_16, :res_128, :res_256, :res_512, :res_1024]
    end

    @testset "properties" begin
        @test names(@query PDS lola > bundle[url]) == [:bundle]
        @test names(@query PDS lola > bundle[prop(url)]) == [:bundle]
        @test names(@query PDS lola > bundle[links][url]) == [:bundle]
        @test names(query(PDS, "lola > bundle[links][url]")) == [:bundle]
        @test names(@query PDS lamp > noextras[regex]) == [:noextras]

        @test names(@query PDS lola > bundle[links = relative]) == [:bundle]
        @test names(@query PDS lola > bundle[url ^= "https://pds-geosciences"]) ==
              [:bundle]
        @test names(@query PDS lola >> bundle > ldec[regex %= "*ldec*"]) == [:ldec]
        @test isempty(@query PDS lola > default[url])

        @test names(@query PDS [values()]) ==
              [:default, :resolution, :projection, :format,
               :bundle, :resolution, :projection, :format,
               :default, :noextras, :default, :default]
        @test names(@query PDS lola > [props()]) ==
              [:bundle, :illumination, :fractal]
    end

    @testset "values" begin
        @test names(@query PDS m3 > default[val() = l1]) == [:default]
        @test names(@query PDS m3 > default[val(2) = l2]) == [:default]
        @test isempty(@query PDS m3 > default[val(3)])
        @test names(@query PDS [val() = filter]) ==
              [:resolution, :projection, :format, :noextras]
    end

    @testset "node names" begin
        @test names(@query PDS [name() = default]) == fill(:default, 5)
        @test names(@query PDS [name() = "default"]) == fill(:default, 5)
        @test names(@query PDS [name() ^= "ld"]) == [:ldam, :ldec, :ldem, :ldrm]

        # Names compare as text, so a Symbol query matches a quoted name.
        q = kdl("\"my node\" 1")
        @test names(@query q var"my node") == ["my node"]
        @test names(@query q "my node") == ["my node"]
    end

    @testset "siblings" begin
        @test names(@query PDS m3 > l1 + l2) == [:l2]
        @test names(@query PDS m3 > l1 + []) == [:l2]
        @test isempty(@query PDS m3 > l1 + default)
        @test names(@query PDS m3 > l1 ++ default) == [:default]
        @test names(@query PDS lola > illumination ++ []) ==
              [:fractal, :resolution, :projection, :format, :default]
        @test names(@query PDS diviner > [] + []) ==
              [:epf, :prp, :pcp, :rcp, :l2, :l3, :default]
        @test names(@query PDS diviner > gcp ++ []) ==
              [:epf, :prp, :pcp, :rcp, :l2, :l3, :default]
    end

    @testset "union and chain flattening" begin
        @test names(@query PDS ovirs || naif) == [:ovirs, :naif]
        @test names(@query PDS m3 > l2 || m3 > l1) == [:l1, :l2]
        @test names(@query PDS m3 > l1 || m3 > l1) == [:l1]
        @test length(@query PDS top() > [] || top() > m3) == 6

        @test names(@query PDS top() > lola >> bundle > ldam + ldec) == [:ldec]
        @test names(@query PDS lola >> bundle > [] || top() > naif > []) ==
              [:ldam, :ldec, :ldem, :ldrm, :kernels, :default]

        # Julia parses these with different grouping than KQL; the macro
        # flattens the chain left-associatively.
        @test names(@query PDS top() > lola >> bundle) == [:bundle, :bundle]
        @test names(@query PDS m3 > l1 + l2) == [:l2]
        @test names(@query PDS diviner > gcp + epf) == [:epf]
    end

    @testset "block form" begin
        roots, kids = @query PDS begin
            top() > []
            m3 > []
        end
        @test roots isa Vector{KDLNode}
        @test names(roots) == ROOTS
        @test names(kids) == [:l1, :l2, :default]

        # A block always yields a tuple, even for one query.
        one = @query PDS begin
            top() > m3
        end
        @test one isa Tuple && length(one) == 1
        @test names(only(one)) == [:m3]
    end

    @testset "show and round-trip" begin
        for s in ["m3 > []", "a || b >> c", "x[val(2) != 1]",
                  "a[url ^= \"https\"]", "[]", "top() > [name() %= \"ies\"]",
                  "a[platform = windows]", "\"my node\" > []"]
            q = KDLQuery(s)
            printed = sprint(show, q)
            @test sprint(show, KDLQuery(printed)) == printed
        end
        @test sprint(show, KDLQuery("a[url]")) == "a[url]"
        @test sprint(show, @query lola > bundle[url ^= "https"]) ==
              "lola > bundle[url ^= \"https\"]"
    end

    @testset "front ends agree" begin
        for (ex, s) in [
            (:(top() > []), "top() > []"),
            (:(m3 > l2 || m3 > l1), "m3 > l2 || m3 > l1"),
            (:(lola >> bundle > []), "lola >> bundle > []"),
            (:(m3 > default[val() = l1]), "m3 > default[val() = l1]"),
            (:(lola > bundle[url ^= "https"]), "lola > bundle[url ^= \"https\"]"),
            (:(diviner > gcp ++ []), "diviner > gcp ++ []"),
        ]
            @test @eval(@query PDS $ex) == query(PDS, s)
        end

        # The string dialect can spell KDL names that Julia syntax cannot.
        d = kdl("my-node { child-node }")
        @test names(query(d, "my-node > child-node")) == [Symbol("child-node")]
        @test names(@query d var"my-node" > var"child-node") == [Symbol("child-node")]
    end

    @testset "compile-time construction" begin
        # A query string literal is parsed during macro expansion and embedded
        # as a callable KDLQuery, so loops and repeated uses do not reparse.
        ex = macroexpand(@__MODULE__, :(query"m3 > []"))
        @test ex isa QuoteNode
        @test ex.value isa KDLQuery
        @test names(ex.value(PDS)) == [:l1, :l2, :default]

        expansion = macroexpand(@__MODULE__, :(@query PDS m3 > []))
        @test expansion isa Expr && expansion.head === :call
        @test expansion.args[1] isa QuoteNode
        @test expansion.args[1].value isa KDLQuery

        q = query"m3 > []"
        @test q === query"m3 > []"
        @test all(names(q(PDS)) == [:l1, :l2, :default] for _ in 1:3)
    end

    @testset "curried and piped forms" begin
        q = @query m3 > []
        @test q isa KDLQuery
        @test names(q(PDS)) == [:l1, :l2, :default]
        @test names(PDS |> q) == [:l1, :l2, :default]
        @test names(PDS |> @query(m3 > [])) == [:l1, :l2, :default]

        qroots, qm3 = @query begin
            top() > []
            m3 > []
        end
        @test qroots isa KDLQuery
        @test names(qroots(PDS)) == ROOTS
        @test names(qm3(PDS)) == [:l1, :l2, :default]
    end

    @testset "string forms" begin
        @test names(KDLQuery("m3 > []")(PDS)) == [:l1, :l2, :default]
        @test names(query"m3 > []"(PDS)) == [:l1, :l2, :default]
        @test names(query`m3 > []`(PDS)) == [:l1, :l2, :default]
        @test names(query(PDS, "m3 > []")) == [:l1, :l2, :default]
        @test names(query(PDS, "top() > []")) == ROOTS
        @test names(query(PDS, "lola >> bundle > ldec[regex %= \"*ldec*\"]")) ==
              [:ldec]
        @test names(query(PDS, "top() > lola >> bundle > ldam + ldec")) == [:ldec]
        @test names(query(PDS, "top() > lola >> bundle")) == [:bundle, :bundle]
        @test names(query(PDS, "[name() ^= \"ld\"]")) ==
              [:ldam, :ldec, :ldem, :ldrm]
    end

    @testset "Julia values" begin
        d = kdl("n #true #false #null 1 1.0 \"1\" foo \"foo\"")
        @test names(@query d n[val() = true]) == [:n]
        @test names(@query d n[val(2) = false]) == [:n]
        @test names(@query d n[val(3) = nothing]) == [:n]
        @test names(@query d n[val(4) = 1]) == [:n]
        @test isempty(@query d n[val(5) = 1])        # 1.0 is not 1
        @test isempty(@query d n[val(4) = 1.0])
        @test names(@query d n[val(6) = "1"]) == [:n]
        @test names(@query d n[val(7) = foo]) == [:n]
        @test names(@query d n[val(8) = "foo"]) == [:n]
        @test isempty(@query d n[val(7) = "foo"])    # Symbol is not String
        @test isempty(@query d n[val(8) = foo])

        # The string dialect parses the same values.
        @test names(query(d, "n[val() = true]")) == [:n]
        @test names(query(d, "n[val(3) = nothing]")) == [:n]
        @test names(query(d, "n[val(7) = foo]")) == [:n]
        @test isempty(query(d, "n[val(7) = \"foo\"]"))

        dnums = kdl("n #inf #-inf #nan")
        @test names(@query dnums n[val() = Inf]) == [:n]
        @test names(@query dnums n[val(2) = -Inf]) == [:n]
        @test names(@query dnums n[val(3) = NaN]) == [:n]
        @test names(query(dnums, "n[val() = Inf]")) == [:n]
        @test names(query(dnums, "n[val(2) = -Inf]")) == [:n]
        @test names(query(dnums, "n[val(3) = NaN]")) == [:n]

        escaped = kdl("n \"a\\nb\"")
        @test names(query(escaped, "n[val() = \"a\\nb\"]")) == [:n]
    end

    @testset "results" begin
        m = only(@query PDS lola > bundle)
        @test m isa KDLNode
        @test nameof(m) === :bundle
        @test m[:url] ==
              "https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/"

        @test names(@query PDS diviner > [url]) ==
              [:gcp, :epf, :prp, :pcp, :rcp, :l2, :l3]
    end

    @testset "errors" begin
        @test_throws KDLQueryError KDLQuery("m3 >")
        @test_throws KDLQueryError KDLQuery("m3 > > l1")
        @test_throws KDLQueryError KDLQuery("a > top()")
        @test_throws KDLQueryError KDLQuery("[nope()]")
        @test_throws KDLQueryError KDLQuery("a[regex \$= \"x\"]")
        @test_throws KDLQueryError KDLQuery("type(m3)")
        @test_throws KDLQueryError KDLQuery("[tag() = hi]")
        @test_throws KDLQueryError KDLQuery("[val() = type(foo)]")
        @test_throws KDLQueryError KDLQuery("[val() = (foo)]")
        @test_throws KDLQueryError KDLQuery("a[val(0)]")
        @test_throws KDLQueryError KDLQuery("[values() = 1]")
        @test_throws KDLQueryError macroexpand(@__MODULE__, :(@query PDS a[values() = 1]))
        @test_throws KDLQueryError KDLQuery("top() + a")
        @test_throws KDLQueryError macroexpand(@__MODULE__, :(@query PDS a[val(0)]))
        @test_throws KDLQueryError macroexpand(@__MODULE__, :(@query PDS top() + a))
        @test_throws KDLQueryError macroexpand(@__MODULE__, :(@query PDS a b))
        @test_throws KDLQueryError macroexpand(@__MODULE__, :(query"m3 >"))

        @test_throws KDLQueryError macroexpand(@__MODULE__, :(@query PDS a > top()))
        @test_throws KDLQueryError macroexpand(@__MODULE__, :(@query PDS type(m3)))
        @test_throws KDLQueryError macroexpand(@__MODULE__, :(@query PDS a[tag() = hi]))
        @test_throws KDLQueryError macroexpand(@__MODULE__,
                                               :(@query PDS a[val() = type(foo)]))
    end
end
