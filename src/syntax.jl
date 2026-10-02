syntax = @syntax :document begin

    :unicode_space => first(
        token('\u0009'), token('\u0020'), token('\u00A0'), token('\u1680'),
        token('\u2000'), token('\u2001'), token('\u2002'), token('\u2003'),
        token('\u2004'), token('\u2005'), token('\u2006'), token('\u2007'),
        token('\u2008'), token('\u2009'), token('\u200A'), token('\u202F'),
        token('\u205F'), token('\u3000'),
    )

    :newline => first(
        tokens("\u000D\u000A"), token('\u000D'), token('\u000A'),
        token('\u0085'), token('\u000B'), token('\u000C'),
        token('\u2028'), token('\u2029'),
    )

    :multiline_comment => seq(
        tokens("/*"),
        :commented_block,
    )

    :commented_block => first(
        tokens("*/"),
        seq(
            first(:multiline_comment, token('*'), token('/'), r"[^*/]+"),
            :commented_block,
        ),
    )

    :singleline_comment => scan(kdl_comment_scan)

    :ws => first(
        :unicode_space,
        :multiline_comment,
    )

    :escline => seq(
        token('\\'),
        many(:ws),
        first(:singleline_comment, :newline),
    )

    :node_space => first(
        seq(many(:ws), :escline, many(:ws)),
        some(:ws),
    )

    :line_space => first(
        :node_space,
        :newline,
        :singleline_comment,
    )

    :bom => token('\uFEFF')

    :version => seq(
        tokens("/-"), many(:unicode_space), tokens("kdl-version"),
        some(:unicode_space), first(token('1'), token('2')),
        many(:unicode_space), :newline,
    )

    :nodes => seq(
        many(:node_or_ws),
        first(:final_node_or_ws, epsilon),
        many(:line_space),
    )

    :final_node_or_ws => seq(
        many(:line_space),
        :final_node,
    )

    :node_or_ws => seq(
        many(:line_space),
        :kdlnode,
    )

    :document => seq(
        first(:bom, epsilon),
        first(:version, epsilon),
        :nodes,
    )

    :slashdash => seq(
        tokens("/-"),
        many(:line_space),
    )

    :kdlnode => first(
        :slashdash_node,
        :node_terminated,
    )

    :slashdash_node => seq(
        :slashdash,
        :final_node,
    )

    :node_terminated => seq(
        :node_base,
        :node_terminator,
    )

    :final_node => first(
        :node_terminated,
        :node_base,
    )

    :node_terminator => first(
        :singleline_comment,
        :newline,
        token(';'),
    )

    :node_base => seq(
        :node_head,
        many(seq(:node_sep, :node_entry)),
        :children_part,
        :node_tail,
    )

    :node_tail => seq(
        many(:node_space),
        first(seq(token('\\'), many(:ws)), epsilon),
    )

    :node_head => seq(
        first(:type, epsilon),
        many(:node_space),
        :sident,
    )

    :node_sep => first(
        :slashdash_sep,
        :node_space,
    )

    :slashdash_sep => seq(
        many(:node_space),
        :slashdash,
    )

    :node_entry => first(
        :prop,
        :value,
    )

    :children_part => seq(
        many(seq(many(:node_space), :slashdash, :node_children)),
        first(seq(many(:node_space), :node_children), epsilon),
        many(seq(many(:node_space), :slashdash, :node_children)),
    )

    :node_children => seq(
        token('{'),
        :nodes,
        first(:final_node, epsilon),
        token('}'),
    )

    :prop => seq(
        :sident,
        many(:node_space),
        token('='),
        many(:node_space),
        :value,
    )

    :value => seq(
        first(:type, epsilon),
        many(:node_space),
        first(:number, :keyword, :sident),
    )

    :type => seq(
        token('('),
        many(:node_space),
        :sident,
        many(:node_space),
        token(')'),
    )

    :ident => scan(kdl_ident_scan)

    :multiline_string => seq(
        tokens("\"\"\""),
        :newline,
        many(:multiline_body),
        tokens("\"\"\""),
    )

    :multiline_body => first(
        :string_escape,
        :ws_escape,
        seq(tokens("\"\""), satisfy(c -> c != '"')),
        seq(token('"'), satisfy(c -> c != '"')),
        satisfy(c -> c != '"'),
    )

    :singleline_string => seq(
        token('"'),
        many(:string_char),
        token('"'),
    )

    :string_char => first(
        :string_escape,
        :ws_escape,
        satisfy(c -> c != '"' && c != '\\' && !is_newline(c)),
    )

    :string_escape => first(
        seq(token('\\'), satisfy(c -> c in "\"\\bfnrts")),
        seq(tokens("\\u{"), r"[0-9a-fA-F]{1,6}", token('}')),
    )

    :ws_escape => seq(
        token('\\'),
        some(first(:unicode_space, :newline)),
    )

    :raw_string => scan(kdl_raw_scan)

    :string => first(
        :multiline_string,
        :singleline_string,
        :raw_string,
    )

    :sident => first(
        :ident,
        :string,
    )

    :keywordnumber => first(
        tokens("#-inf"),
        tokens("#inf"),
        tokens("#nan"),
    )

    :keyword => first(
        tokens("#true"),
        tokens("#false"),
        tokens("#null"),
    )

    :integer => r"[0-9][0-9_]*"

    :decimal => seq(
        first(token('+'), token('-'), epsilon),
        :integer,
        first(seq(token('.'), :integer), epsilon),
        first(:exponent, epsilon),
    )

    :exponent => seq(
        r"e"i,
        first(token('+'), token('-'), epsilon),
        :integer,
    )

    :hex => seq(
        first(token('+'), token('-'), epsilon),
        tokens("0x"),
        r"[0-9a-fA-F][0-9a-fA-F_]*",
    )

    :octal => seq(
        first(token('+'), token('-'), epsilon),
        tokens("0o"),
        r"[0-7][0-7_]*",
    )

    :binary => seq(
        first(token('+'), token('-'), epsilon),
        tokens("0b"),
        r"[01][01_]*",
    )

    :number => first(
        :keywordnumber,
        :hex,
        :octal,
        :binary,
        :decimal,
    )
end
