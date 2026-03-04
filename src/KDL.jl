module KDL

export ⇜
export ←
export KDLNode

# grammar reference: https://kdl.dev/spec/#name-slashdash-comments

using  Match
import PikaParser as P
using Term: Tree, Theme

struct KDLNode
    a :: Union{Dict, Missing}
    d :: Union{Dict, Missing}
    KDLNode(body::Pair...)= new(Dict(), Dict(body))
    #=KDLNode(a, b) = new(a, b)=#
    #=KDLNode(arg)     = new(Dict(arg))=#
    KDLNode() = new(Dict(), Dict())
    KDLNode(_::Missing, _::Missing) = new(missing, missing)
    KDLNode(a::Dict, d::Dict) = new(a, d)
    KDLNode(a::Dict, d::Missing) = new(a, d)
    KDLNode(_::Missing, d::Dict) = new(missing, d)
end

Base.show(io::IO, k::KDLNode) =
    print(io, "KDLNode { ",
              "Args:", k.a, " ",
              "Body:", k.d, " }"
    )

Base.merge(a, _::Missing) = a
Base.merge(_::Missing, b) = b
Base.merge(_::Missing, _::Missing) = missing

Base.merge(k1::KDLNode, k2::KDLNode) =
    KDLNode(merge(k1.a, k2.a), merge(k1.d, k2.d))

Base.merge(k::KDLNode, d::Dict) = KDLNode(k.a, merge(k.d, d))
Base.merge(d::Dict, k::KDLNode) = KDLNode(k.a, merge(k.d, d))
Base.merge!(k::KDLNode, d::Dict) = begin
    merge!(k.d, d)
    k
end

Base.merge!(k1::KDLNode, k2::KDLNode) = begin
    merge!(k1.d, copy(k2.d))
    merge!(k1.a, copy(k2.a))
    k1
end

Base.empty!(k::KDLNode) = empty!(k.d)
Base.getindex(k :: KDLNode, i) = get(k.d, i, false)
Base.getindex(k :: KDLNode, is...) = get(k.d, is, false)
function Base.getindex(k :: KDLNode, i :: Union{Vector,Tuple}) 
    length(i) == 0 ? error("Zero-length index for $k") :
    length(i) == 1 ? k[i[1]] : k[i[1]][i[2:end]]
end
Base.haskey(k :: KDLNode, i) = haskey(k.d, i)
Base.setindex!(k :: KDLNode, i,  v)    = k.d[i] = v
#=Base.setindex!(k :: KDLNode, is, v) = k.d[is] = v=#
function Base.setindex!(
    k :: KDLNode,
    i :: Union{Vector,Tuple},
    v) 

    length(i) == 0 ? error("Zero-length index for $k") :
    length(i) == 1 ? setindex!(k, i[1], v)             :
                     setindex!(k[i[1]], i[2:end], v)
end

(k::KDLNode)(i)   = k.a[i]
(k::KDLNode)(i,n) = k.a[i] = n

⇜(k::KDLNode, i) = !ismissing(k[i]) 
←(k::KDLNode, i) = ismissing(k[i])

syntax = P.@syntax :kdl begin

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
            #=:signed_ident,=#
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

    :arg => first(
        :prop,
        :value,
    ),

    :node_args => some(:arg),

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

    :knode => first(
        :slashdash,
        :node
    ),

    :kdl => seq(
        :ws,
        many(:knode)
    )
end

semantics = P.@semantics :kdl m v begin

    :boolean => begin
        @match m.view begin
            "#true"  => true
            "#false" => false
        end
    end

    :keywordnumber => begin
        @match m.view begin
            "#inf"  => Inf
            "#-inf" => -Inf
            "#nan"  => NaN
        end
    end

    :keyword => begin
        !isnothing(v)     && return v[1]
        m.view == "#null" && return nothing
    end

    :sign => begin
        @match m.view begin
            "-" => :-
            "+" => :+
            _   => nothing
        end
    end

    :ident => Symbol(m.view)
    :type => KDLNode(:type => v[3])
    :value => v[2][1]

    #=:signed_ident => begin=#
    #=    # this will probably break.=#
    #=    @info "signed ident"=#
    #=    @show v=#
    #=    isnothing(v[1]) && return v[2]=#
    #=    return Dict(=#
    #=        v[2] => Dict(:sign => v[1]),=#
    #=    )=#
    #=end=#

    #=:string => begin=#
    #=    @info "String"=#
    #=    @show v=#
    #=    m.view=#
    #=end=#

    :prop => (v[1], v[5])

    :node_children => begin
        @info ":node_children"
        @show m.view
        @show v[3]
        # fixme -- turn this into a dictionary
        ret = Dict()
        for node in v[3]
            @show "Iterating" node
            s, a, b = node
            @show merge!(ret, Dict(s => KDLNode(a, b)))
        end
        @show ret
    end

    :arg => v[1] isa Tuple ? v[1] : v[1], missing

    :node_args => begin
        args = Dict()
        @show v
        for elem in v
            @info "node_args iteration"
            @show elem

            @match elem begin

                (k, v) => begin
                    args[k] = v
                end

                v => begin
                    args[v] = missing
                end
            end
        end
        args
    end

    :node_with_children => begin
        @info ":node_with_children"
        @show m.view
        @show v
        @show (v[1], v[3], v[5])
    end

    :node_only_params => begin
        @info ":node_only_params"
        @show m.view
        @show (v[1], v[3], missing)
    end

    :node_only_children => begin
        @info ":node_only_children"
        @show m.view
        @show v
        @show (v[1], missing, v[3])
    end

    :node  => begin
        ret = @match v[1] begin
            (s, args, body) => (s, args,    body)
             s :: Symbol    => (s, missing, missing)
            _ => error("Weird node: $(v[1])")
        end
        @show ret
    end

    :knode => v[1]

    :kdl => begin
        @info ":kdl"
        @show v[2]
        ret = KDLNode()
        for node in v[2]
            @info "kdl: iterating"
            @show node
            s, a, b = node
            merge!(ret, Dict(s => KDLNode(a, b)))
        end
        ret
    end
end

end # module KDL
