module KDL

# grammar reference: https://kdl.dev/spec/#name-slashdash-comments

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
        tokens("\u000D\u000A"), # carriage return + newline
        token('\u000D'),        # carriage return
        token('\u000A'),        # line feed
        token('\u0085'),        # next line
        token('\u000B'),        # vertical tab
        token('\u000C'),        # form feed
        token('\u2028'),        # line separator
        token('\u2029'),        # paragraph separator
    ), 

    # escaped newlines, spaces in nodes, and linespace.
    # TODO: add end of file
    #=:escline => seq(=#
    #=    token('\\'),=#
    #=    maybe(:ws),=#
    #=    first(=#
    #=        #=:singleline_comment,=#=#
    #=        :newline,=#
    #=        P.end_of_input=#
    #=    )=#
    #=),=#

    #=:nodespace => first(=#
    #=    seq(many(:ws),=#
    #=        :escline,=#
    #=    ),=#
    #=    some(:ws)=#
    #=),=#
    :linespace => first(
        :unicode_space,
        :newline,
        :singleline_comment
    ),

    #=:ws => first(=#
    #=    :unicode_space,=#
    #=    :multiline_comment,=#
    #=),=#

    :slashdash => seq(
        tokens("/-"),
        maybe(some(:linespace)),
    ),

    # NOTE: requires checking.
    :singleline_comment => seq(
        tokens("//"),
        many(seq(
            not_followed_by(:newline),
            satisfy(_ -> true),
        )),
        :newline,
    ),

    #=:multiline_comment => seq(=#
    #=    tokens("/*"),=#
    #=    many(r"(?!\*/).{2}"),=#
    #=    tokens("*/"),=#
    #=),=#

    #=:commentblock => first(=#
    #=    tokens("*/"),=#
    #=    seq(=#
    #=        first(=#
    #=            :multiline_comment,=#
    #=            token('*'),=#
    #=            token('/'),=#
    #=            r"[^*/]+",=#
    #=        ),=#
    #=        :commentblock=#
    #=    ),=#
    #=),=#

    :bom => maybe(token('\uFEEF')),

    :boolean => first(
        tokens("#true"),
        tokens("#false")
    ),

    :keywordnumber => first(
        tokens("#inf"),
        tokens("#-inf"),
        tokens("#nan")
    ),

    :keyword => first(
        :boolean,
        tokens("#null")
    ),

    :sign => first(
        token('+'),
        token('-')
    ),

    :integer => r"[0-9]+[0-9_]*",

    :decimal => seq(
        maybe(:sign),
        :integer,
        maybe(seq(
            token('.'),
            :integer
        )),
        maybe(:exponent)
    ),

    :exponent => seq(
        r"e"i,
        maybe(:sign),
        :integer
    ),

    :hex => seq(
        maybe(:sign),
        tokens("0x"),
        r"[0-9a-fA-F]+[0-9a-fA-F_]*",
    ),

    :octal => seq(
        maybe(:sign),
        tokens("0o"),
        r"[0-7]+[0-7_]*",
    ),

    :binary => seq(
        maybe(:sign),
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


    :version => seq(
        tokens("/-"),
        maybe(some(:unicode_space)),
        tokens("kdl-version"),
        some(:unicode_space),
        first(
            token('1'),
            token('2')
        ),
        maybe(some(:unicode_space)),
        :newline
    ),

    # N.B. Pika parsing doesn't care about backtrack
    :string => first(
        :identifier_string,
        :quoted_string,
        :raw_string
    ),

    :identifier_string => first(
        :unambiguous_ident,
        :signed_ident,
        :dotted_ident
    ),

    #=:disallowed_keyword_identifiers => first(=#
    #=    tokens("true"),=#
    #=    tokens("false"),=#
    #=    tokens("null"),=#
    #=    tokens("inf"),=#
    #=    tokens("-inf"),=#
    #=    tokens("nan"),=#
    #=),=#

    :unambiguous_ident => seq(
        not_followed_by(tokens("true")),
        not_followed_by(tokens("false")),
        not_followed_by(tokens("null")),
        not_followed_by(tokens("inf")),
        not_followed_by(tokens("-inf")),
        not_followed_by(tokens("nan")),
        not_followed_by(r"[\.0-9]"),
        some(:identifier_char)
    ),

    :signed_ident => seq(
        :sign,
        maybe(seq(
            not_followed_by(r"[\.0-9]"),
            some(:identifier_char)
        ))
    ),

    :dotted_ident => seq(
        maybe(:sign),
        token('.'),
        seq(
            not_followed_by(r"[0-9]"),
            :identifier_char
        ),
        many(:identifier_char),
    ),

    # TODO: not_followed_by: is this ok?
    :identifier_char => seq(
        not_followed_by(:unicode_space),
        not_followed_by(:newline),
        not_followed_by(r"[\\/(){};\[\]\"#=]"),
        satisfy(_ -> true)
    ),


    :singleline_string => seq(
        token('"'),
        many(satisfy(x -> x != '"')),
        token('"'),
    ),

    :multiline_string => seq(
        tokens("\"\"\""),
        :newline,
        r"(?!\"\"\").{3}",
        tokens("\"\"\""),
    ),

    :quoted_string => first(
        :singleline_string,
        :multiline_string,
    ),

    :raw_string => seq(
        token('#'),
        r"[^#]*",
        token('#'),
    ),


    :nodes => seq(
        maybe(some(seq(
            :mlinespace => maybe(some(:linespace)),
            :node
        ))),
        :mlinespace
    ),

    :basenode => seq(
        maybe(:slashdash),
        maybe(:type),
        maybe(some(:unicode_space)),
        :string,
        maybe(some( seq(some(:unicode_space), maybe(:slashdash), :node_prop_or_arg))),
        maybe(some( seq(some(:unicode_space), :slashdash,        :node_children))),
        maybe(seq(some(:unicode_space), :node_children)),
        maybe(some(( seq(some(:unicode_space), :slashdash,        :node_children)))),
        maybe(some(:unicode_space)),
    ),

    :node => seq(
        :basenode,
        :node_terminator
    ),

    :finalnode => seq(
        :basenode,
        maybe(:node_terminator)
    ),

    :node_prop_or_arg => first(
        :prop,
        :value
    ),

    :node_children => seq(
        token('{'),
        :nodes,
        maybe(:finalnode),
        token('}'),
    ),

    :node_terminator => first(
        #=:singleline_comment,=#
        :newline,
        token(';'),
        P.end_of_input
    ),

    # props and values
    :prop => seq(
        :string,
        many(:unicode_space),
        token('='),
        many(:unicode_space),
        :value
    ),

    :value => seq(
        maybe(:type),
        many(:unicode_space),
        first(
            :string,
            :number,
            :keyword
        )
    ),

    :type => seq(
        token('('),
        many(:unicode_space),
        :string,
        many(:unicode_space),
        token(')')
    ),



    :kdl => seq(
        :bom,       # byte order marker (unicode)
        :version,   # KDL version declaration
        :nodes      # KDL nodes.
    )
end

end # module KDL


    #=:mlsbody => many(seq(=#
    #=    maybe(r"(\"|\"\")"),=#
    #=    :strchar,=#
    #=)),=#
    #
    #
    #
    #=:strchar => first(=#
    #=    :fmtchar,=#
    #=    :unicode_escape,=#
    #=    :ws_esc,=#
    #=    r"[^\\\"]",=#
    #=),=#


    #=:ws_esc => seq(=#
    #=    token('\\'),=#
    #=    satisfy(isspace),=#
    #=),=#
    #:fmtchar => r"\\[bfnrts\\\"]",
    #=:unicode_escape => seq(=#
    #=    tokens("\\u{"),=#
    #=    r"[0-9a-fA-F]{1,6}",=#
    #=    token('}'),=#
    #=),=#
