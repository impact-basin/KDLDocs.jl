syntax = P.@syntax :kdl begin

    :unicode_space => first(
        token('\u0009'), token('\u0020'), token('\u00A0'),
        token('\u1680'), token('\u2000'), token('\u2001'),
        token('\u2002'), token('\u2003'), token('\u2004'),
        token('\u2005'), token('\u2006'), token('\u2007'),
        token('\u2008'), token('\u2009'), token('\u200A'),
        token('\u202F'), token('\u205F'), token('\u3000'),
    )

    :newline => first(
        tokens("\u000D\u000A"),           token('\u000D'),
        token('\u000A'), token('\u0085'), token('\u000B'),
        token('\u000C'), token('\u2028'), token('\u2029'),
    )

    :singleline_comment => seq(
        tokens("//"),
        many(seq(
            not_followed_by(:newline),
            satisfy(_ -> true),
        )),
        :newline,
    )

    :multiline_comment => seq(
        tokens("/*"),
        many(r"(?!\*/).{2}"),
        tokens("*/"),
    )

    :ws => many(first(
        :multiline_comment,
        :singleline_comment,
        :unicode_space,
        :newline
    ))

    #=:bom => token('\uFEEF'),=#

    :boolean => first(
        tokens("#true"),
        tokens("#false")
    )

    :keywordnumber => first(
        tokens("#-inf"),
        tokens("#inf"),
        tokens("#nan")
    )

    :keyword => first(
        :boolean,
        tokens("#null")
    )

    :sign => first(
        token('+'),
        token('-'),
        epsilon,
    )

    :integer => seq(
        r"[0-9]+[0-9_]*",
    )

    :exponent => first(seq(
        r"e"i,
        :sign,
        :integer,
    ), epsilon)

    :decpart => first(seq(
        token('.'),
        :integer,
    ), epsilon)

    :decimal => seq(
        :sign,
        :integer,
        :decpart,
        :exponent,
    )

    :hex => seq(
        :sign,
        tokens("0x"),
        r"[0-9a-fA-F]+[0-9a-fA-F_]*",
    )

    :octal => seq(
        :sign,
        tokens("0o"),
        r"[0-7]+[0-7_]*",
    )

    :binary => seq(
        :sign,
        tokens("0b"),
        r"[0-1]+[0-1_]*",
    )

    :number => first(
        :keywordnumber,
        :hex,
        :octal,
        :binary,
        :decimal
    )

    :ident => seq(
        not_followed_by(tokens("true")),
        not_followed_by(tokens("false")),
        not_followed_by(tokens("null")),
        not_followed_by(tokens("inf")),
        not_followed_by(tokens("-inf")),
        not_followed_by(tokens("nan")),
        r"[a-zA-Z_]+[a-zA-Z0-9_]*",
    )

    #=:signed_ident => seq(=#
    #=    :sign,=#
    #=    :ident,=#
    #=),=#

    #=:dotted_ident => seq(=#
    #=    :sign,=#
    #=    token('.'),=#
    #=    :ident,=#
    #=),=#

    :singleline_string => r"[\"]([^\"\\]|\\.)*\""
    :multiline_string  => r"(\"\"\")([^\"\\]|\\[\s\S])*(\"\"\")"
    :raw_string => r"#([=]+)((.|\n)*)(\1)#"

    #=:identifier_string => first(=#
    #=    :dotted_ident,=#
    #=    :signed_ident,=#
    #=    :ident,=#
    #=),=#

    :string => first(
        :multiline_string,
        :singleline_string,
        :raw_string,
    )

    :sident => first(
        :ident,
        :string
    )

    :type => seq(
        token('('), :ws,
        :ident,     :ws,
        token(')'), :ws,
    )

    :value => seq(
        first(:type, epsilon),
        first(
            :number,
            :keyword,
            :ident,
            :string,
        ),
    )

    :prop => seq(
        :sident,    many(:unicode_space),
        token('='), many(:unicode_space),
        :value,     many(:unicode_space),
    )

    :node_children => seq(
        token('{'),  :ws,
        some(:node), :ws,
        token('}'),  :ws,
    )

    :semicolon => token(';')

    :node_end => first(
        :node_children,
        :semicolon,
        :newline,
        end_of_input
    )

    :arg => first(
        :prop,
        :value,
    )

    :args => some(seq(
        :arg,
        many(:unicode_space)
    )),

    :node_args => first(
        :args,
        epsilon
    )

    :node => seq(
        :sident,    many(:unicode_space),
        :node_args, many(:unicode_space),
        :node_end,  :ws,
    )

    :slashdash => seq(
        tokens("/-"),
        :node,
    )

    :kdlnode => first(
        :slashdash,
        :node
    )

    :kdl => seq(
        :ws,
        many(:kdlnode)
    )
end
