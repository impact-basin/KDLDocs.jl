module KDL

# grammar reference: https://kdl.dev/spec/#name-slashdash-comments

function to_dict(submatches)
    ret = Dict{Symbol, Any}()
    for elem in submatches
        if elem isa Dict
            @info "to_dict(): processing element"
            @show elem
           if haskey(elem, :name)
                ret[elem[:name]] = copy(elem)
                delete!(ret[elem[:name]], :name)
            end
        end
    end
end

using Match
import PikaParser as P

g = P.@grammar :kdl begin

    :unicode_space => first(
        token('\u0009'), token('\u0020'), token('\u00A0'),
        token('\u1680'), token('\u2000'), token('\u2001'),
        token('\u2002'), token('\u2003'), token('\u2004'),
        token('\u2005'), token('\u2006'), token('\u2007'),
        token('\u2008'), token('\u2009'), token('\u200A'),
        token('\u202F'), token('\u205F'), token('\u3000'),
    ),

    :newline => first(
        tokens("\u000D\u000A"),           token('\u000D'),
        token('\u000A'), token('\u0085'), token('\u000B'),
        token('\u000C'), token('\u2028'), token('\u2029'),
    ), 

    :singleline_comment => seq(
        tokens("//"),
        many(seq(
            not_followed_by(:newline),
            satisfy(_ -> true),
        )),
        :newline,
    ),

    :multiline_comment => seq(
        tokens("/*"),
        many(r"(?!\*/).{2}"),
        tokens("*/"),
    ),

    :ws => many(first(
        :multiline_comment,
        :singleline_comment,
        :unicode_space,
        :newline
    )),

    #=:bom => token('\uFEEF'),=#

    :boolean => first(
        tokens("#true"),
        tokens("#false")
    ),

    :keywordnumber => first(
        tokens("#-inf"),
        tokens("#inf"),
        tokens("#nan")
    ),

    :keyword => first(
        :boolean,
        tokens("#null")
    ),

    :sign => first(
        token('+'),
        token('-'),
        epsilon,
    ),

    :integer => seq(
        :unicode_space,
        r"[0-9]+[0-9_]*",
        :unicode_space,
    ),

    :exponent => seq(
        r"e"i,
        :sign,
        :integer
    ),

    :decimal => seq(
        :sign,
        :integer,
        maybe(seq(
            token('.'),
            :integer
        )),
        maybe(:exponent)
    ),

    :hex => seq(
        :sign,
        tokens("0x"),
        r"[0-9a-fA-F]+[0-9a-fA-F_]*",
    ),

    :octal => seq(
        :sign,
        tokens("0o"),
        r"[0-7]+[0-7_]*",
    ),

    :binary => seq(
        :sign,
        tokens("0b"),
        r"[0-1]+[0-1_]*",
    ),

    :number => first(
        :keywordnumber,
        :hex,
        :octal,
        :binary,
        :decimal
    ),

    :ident => seq(
        not_followed_by(tokens("true")),
        not_followed_by(tokens("false")),
        not_followed_by(tokens("null")),
        not_followed_by(tokens("inf")),
        not_followed_by(tokens("-inf")),
        not_followed_by(tokens("nan")),
        r"[a-zA-Z_]+[a-zA-Z0-9_]*",
    ),

    :signed_ident => seq(
        :sign,
        :ident,
    ),

    #=:dotted_ident => seq(=#
    #=    :sign,=#
    #=    token('.'),=#
    #=    :ident,=#
    #=),=#

    #=:singleline_string => seq(=#
    #=    token('"'),=#
    #=    many(satisfy(x -> x != '"')),=#
    #=    token('"'),=#
    #=),=#

    #=:multiline_string => seq(=#
    #=    tokens("\"\"\""),=#
    #=    :newline,=#
    #=    r"(?!\"\"\").{3}",=#
    #=    tokens("\"\"\""),=#
    #=),=#

    #=:raw_string => seq(=#
    #=    token('#'),=#
    #=    r"[^#]*",=#
    #=    token('#'),=#
    #=),=#

    #=:quoted_string => first(=#
    #=    :singleline_string,=#
    #=    #=:multiline_string,=#=#
    #=),=#

    #=:identifier_string => first(=#
    #=    :dotted_ident,=#
    #=    :signed_ident,=#
    #=    :ident,=#
    #=),=#

    #=:string => first(=#
    #=    #=:raw_string,=#=#
    #=    #=:quoted_string,=#=#
    #=    :ident,=#
    #=),=#

    :type => seq(
        token('('), :ws,
        :ident,     :ws,
        token(')'), :ws,
    ),

    :value => seq(
        maybe(:type),
        first(
            :number,
            :keyword,
            :signed_ident,
            :ident, # :string
        ),
        :ws,
    ),

    :prop => seq(
        :ident,     :ws,
        token('='), :ws,
        :value,     :ws,
    ),

    :node_children => seq(
        token('{'),  :ws,
        some(:node), :ws,
        token('}'),  :ws,
    ),

    :node_args => some(first(
        :prop,
        :value
    )),

    :node_with_children => seq(
        :ident,         :ws,
        :node_args,     :ws,
        :node_children, :ws,
    ),

    :node_only_params => seq(
        :ident,     :ws,
        :node_args, :ws,
    ),

    :node_only_children => seq(
        :ident,         :ws,
        :node_children, :ws,
    ),

    :node => first(
        :node_with_children,
        :node_only_children,
        :node_only_params,
        :ident
    ),

    :slashdash => seq(
        tokens("/-"),
        :node,
    ),

    :nodes => some(first(
        :slashdash,
        :node
    )),

    :kdl => seq(
        :ws,
        first(
            :nodes,
            :node,
            #=:ident=#
        )
    )
end

kdl = P.@evaluate :kdl m v begin

    :boolean => begin
        Dict(:value => @match m.view begin
            "#true"  => true
            "#false" => false
        end)
    end

    :keywordnumber => begin
        Dict(:value => @match m.view begin
            "#inf"  => Inf
            "#-inf" => -Inf
            "#nan"  => NaN
        end)
    end

    :keyword => begin
        @info "keyword"
        @show v
        !isnothing(v)     && return v[1]
        m.view == "#null" && return nothing
    end

    :sign => begin
        @match m.view begin
            "-" => :minus
            "+" => :plus
            ""  => :plus
        end
    end

    :ident => begin
        Dict(
            :name  => Symbol(m.view),
        )
    end

    :signed_ident => begin
        return Dict(
            :v[2] => Dict(:sign => v[1]),
        )
    end

    #=:string => begin=#
    #=    @info "String"=#
    #=    @show v=#
    #=    m.view=#
    #=end=#

    :type => begin
        Dict(:type => v[3])
    end

    :value => begin
        Dict(
            :value => v[2],
            :type  => v[1],
        )
    end

    :prop => begin
        Dict(
            v[1] => v[5]
        )
    end

    :node_children => begin
        v[3]
    end

    :node_args => begin
        v
    end

    :node_with_children => begin
        @info "Node with children and args"
        @show v
        Dict(
            :name => v[1],
            :args => v[3],
            :body => v[5],
        )
    end

    :node  => begin
        @info "Node"
        to_dict(v)
    end

    :nodes => begin
        @info "Nodes"
        @show m.view
        @show v
        to_dict(v)
    end

    :kdl => begin
        @info "KDL"
        v[2]
    end
end

end # module KDL
