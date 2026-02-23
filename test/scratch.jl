import PikaParser as P

# grammar reference: https://kdl.dev/spec/#name-slashdash-comments

g = P.@grammar :kdl begin

    :kdl     => seq(:bom, :version, :nodes)
    :bom     => first(token('\uFEEF'), epsilon),
    :version => seq(tokens("/-"),          many(:ucws),
                    tokens("kdl-version"), some(:ucws),
                    first(token('1'), token('2'))),

    # node declarations
    :nodes => seq(many(seq(:linespace, :node)), many(:linespace)),
    :basenode =>
        seq(:slashdashp,
            first(:type, epsilon),
            many(:nodespace),
            :string,
            many( seq(some(:nodespace), :slashdashp, :node_prop_or_arg)),
            many( seq(some(:nodespace), :slashdash,  :node_children)),
            first(seq(some(:nodespace), :node_children), epsilon),
            many( seq(some(:nodespace), :slashdash, :node_children)),
            many(:nodespace),
        ),

    :node      => seq(:basenode, :node_terminator),
    :finalnode => seq(:basenode, first(:node_terminator, epsilon)),

    # entries
    :node_prop_or_arg => first(:prop, :value),
    :node_children    => seq(token('{'), :nodes, first(:finalnode, epsilon)),
    :node_terminator  => first(:singleline_comment, :newline, token(';')),

    # props and values
    :prop  => seq(:string, many(:node_space), token('='), many(:node_space), :value),
    :value => seq(first(:type, epsilon), many(:node_space), first(:string, :number, :keyword)),

    :string => first(:identifier_string, :quoted_string, :raw_string),
    :identifier_string => first(:unambiguous_ident, :signed_ident, :dotted_ident),
    :unambiguous_ident => seq(not_followed_by(tokens("true")),
                              not_followed_by(tokens("false")),
                              not_followed_by(tokens("null")),
                              not_followed_by(tokens("inf")),
                              not_followed_by(tokens("-inf")),
                              not_followed_by(tokens("nan")),
                              not_followed_by(:digit),
                              not_followed_by(:sign),
                              not_followed_by(token('.')),
                              some(:identifier_char)),

    :signed_ident =>
        seq(:sign,
            first(
                seq( not_followed_by(:digit),
                    not_followed_by(token('.')),
                    some(:identifier_char)
                ),
                epsilon
            )
        ),

    :sign => first(token('+'), token('-')),
    :digit => r"[0-9]",
    :digund => r"[0-9_]",
    :hexdigit => r"[0-9a-fA-F]",
    :hexdigund => r"[0-9a-fA-F_]",
    :octdigit => r"[0-7]",
    :integer => seq(:digit, many(:digund)),
    :exponent => seq(first(token('e'), token('E')),
                     first(:sign, epsilon),
                     :integer),
    :hex => seq(first(:sign, epsilon),
                tokens("0x"),
                :hexdigit,
                many(:hexdigund)),


    :keyword => first(:boolean, tokens("#null")),
    :keywordnumber => first(tokens("#inf"),
                            tokens("#-inf"),
                            tokens("#nan")),
    :boolean => first(tokens("#true"), tokens("#false")),

    # whitespace definition, excluding newlines
    :ucws => seq(not_followed_by(:newline), satisfy(isspace)),
    :ws   => first(:ucws, :multiline_comment),

    # newlines
    :newline => first(tokens("\u000D\u000A"), # carriage return + newline
                      token('\u000D'),  # carriage return
                      token('\u000A'),  # line feed
                      token('\u0085'),  # next line
                      token('\u000B'),  # vertical tab
                      token('\u000C'),  # form feed
                      token('\u2028'),  # line separator
                      token('\u2029')), # paragraph separator

    # escaped newlines, spaces in nodes, and linespace.
    :escline   => seq('\\', many(:ws),
                      first(:singleline_comment,
                            :newline)),
    :nodespace => first(seq(many(:ws), :escline, many(:ws)),
                        some(:ws)),
    :linespace => first(:nodespace, :newline, :singleline_comment),

    :notnl => seq(not_followed_by(:newline), satisfy(_ -> true)),
    :singleline_comment => seq(tokens("//"), many(:notnl), :newline),
    :multiline_comment  => seq(tokens("/*"), :commentblock),
    :noteoc => r"[^*/]+",
    :commentblock => first(tokens("*/"),
                           seq(first(:multiline_comment,
                                     token('*'),
                                     token('/'),
                                     :noteoc),
                               :commentblock)),
    :slashdash => seq(tokens("/-"), many(:linespace)),
    :slashdashp => first(:slashdash, epsilon),
                                 
end
