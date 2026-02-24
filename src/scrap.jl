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
    #
    # escaped newlines, spaces in nodes, and linespace.
    # TODO: add end of file
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
    #=:escline => seq(=#
    #=    token('\\'),=#
    #=    many(first(=#
    #=        :singleline_comment,=#
    #=        :unicode_space,=#
    #=    )),=#
    #=    :newline=#
    #=),=#
    #=:version => seq(=#
    #=    tokens("/-"),=#
    #=    maybe(some(:unicode_space)),=#
    #=    tokens("kdl-version"),=#
    #=    some(:unicode_space),=#
    #=    first(=#
    #=        token('1'),=#
    #=        token('2')=#
    #=    ),=#
    #=    maybe(some(:unicode_space)),=#
    #=    :newline=#
    #=),=#
    #
    #
    #
    :kdl => seq(
        maybe(:bom),
        maybe(:version),
        :nodes 
    )
    :linespace => first(
        :singleline_comment,
        :unicode_space,
        :newline,
    ),
