module KDL

# grammar reference: https://kdl.dev/spec/#name-slashdash-comments

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

    #=:signed_ident => seq(=#
    #=    :sign,=#
    #=    :ident,=#
    #=),=#

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

    #=:type => seq(=#
    #=    token('('),=#
    #=    :ws,=#
    #=    :ident,=#
    #=    :ws,=#
    #=    token(')')=#
    #=),=#

    :value => seq(
        #=maybe(:type),=#
        first(
            :number,
            :keyword,
            :ident, # :string
        ),
        :ws,
    ),

    :prop => seq(
        :ident,
        :ws,
        token('='),
        :ws,
        :value,
        :ws,
    ),

    :node_children => seq(
        token('{'),  :ws,
        many(:node), :ws,
        token('}'),
    ),

    :node_args => some(first(
        :prop,
        :value
    )),

    :node_params => first(
        seq(:node_args, :node_children),
        :node_args,
        :node_children,
    ),

    :node => seq(
        :ident,
        :ws,
        :node_params,
        :ws,
        first(
            token(';'),
            :singleline_comment,
            :newline,
            epsilon
        ),
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
        @info "boolean"
        @show m.view
        @match m.view begin
            "#true"  => true
            "#false" => false
        end
    end

    :keywordnumber => begin
        @info "keywordnumber"
        @show m.view
        @match m.view begin
            "#inf"  => Inf
            "#-inf" => -Inf
            "#nan"  => NaN
        end
    end

    :keyword => begin
        !isnothing(v) && return v[1]
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
        @info "Ident"
        @show m.view
        Symbol(m.view)
    end

    #=:string => begin=#
    #=    @info "String"=#
    #=    @show v=#
    #=    m.view=#
    #=end=#

    :prop => begin
        @info "Prop"
        @show m.view
        @show v
        v[1] => v[5]
    end

    :node  => begin
        @info "Node"
        @show m.view
        @show v
        v[1]
    end

    :nodes => begin
        @info "Nodes"
        @show m.view
        @show v
        v
    end

    :kdl => begin
        @info "KDL"
        @show m.view
        @show v
        v
    end
end

end # module KDL
