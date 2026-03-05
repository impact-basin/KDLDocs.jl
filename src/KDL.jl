# █  ▄▀ █▀▀▀▄ █     █▀▀▀▄  ▄▄▄   ▄▄▄▄  ▄▄▄    ▀ █
# █▀▀▄  █   █ █     █   █ █   █ █     ▀▄▄▄    █ █
# █   █ █▄▄▄▀ █▄▄▄▄ █▄▄▄▀ ▀▄▄▄▀ ▀▄▄▄▄ ▄▄▄▄▀ ▄ █ █▄
# A parser for the KDL document language.   ▄▄█   
                                                  
module KDL

using  Match
using  StyledStrings
import PikaParser as P

export ⇜
export ←
export KDLNode

struct KDLNode
    a :: Union{Dict, Missing}
    d :: Union{Dict, Missing}
    KDLNode(body::Pair...)= new(Dict(), Dict(body))
    KDLNode() = new(Dict(), Dict())
    KDLNode(_::Missing, _::Missing) = new(missing, missing)
    KDLNode(a::Dict, d::Dict) = new(a, d)
    KDLNode(a::Dict, d::Missing) = new(a, d)
    KDLNode(a::Missing, d::Dict) = new(a, d)
end


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
        r"[0-9]+[0-9_]*",
    ),

    :exponent => maybe(seq(
        r"e"i,
        :sign,
        :integer,
    )),

    :decpart => maybe(seq(
        token('.'),
        :integer,
    )),

    :decimal => seq(
        :sign,
        :integer,
        :decpart,
        :exponent,
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

    :singleline_string => r"[\"]([^\"\\]|\\.)*\"",
    :multiline_string  => r"(\"\"\")([^\"\\]|\\[\s\S])*(\"\"\")",
    :raw_string => r"#([=]+)((.|\n)*)(\1)#",

    #=:identifier_string => first(=#
    #=    :dotted_ident,=#
    #=    :signed_ident,=#
    #=    :ident,=#
    #=),=#

    :string => first(
        :multiline_string,
        :singleline_string,
        :raw_string,
    ),

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
            :ident,
            :string,
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
            "-" => -1
            "+" =>  1
            _   =>  1
        end
    end

    :integer => begin
        parse(Int, m.view)
    end

    :exponent => begin
        m.view == "" && return nothing
        v[1][2] * v[1][3]
    end

    :decpart => begin
        m.view == "" && return nothing
        v[1][2] * 10^(-ceil(log10(v[1][2])))
    end

    :decimal => begin
        x = v[1] * v[2]
        if !isnothing(v[3])
            x += v[3]
        end
        if !isnothing(v[4])
            x *= 10^v[4]
        end
        x
    end

    :hex    => parse(Int, m.view)
    :octal  => parse(Int, m.view)
    :binary => parse(Int, m.view)
    :number => v[1]

    :ident => Symbol(m.view)
    :type => KDLNode(:type => v[3])
    :value => v[2][1]

    :singleline_string => begin
        @show ":singleline_string" m.view
        kdl_sparse(m.view[2:end-1])
    end

    :multiline_string => begin
        @show ":multiline_string" m.view
        kdl_sparse(m.view[4:end-3])
    end

    :raw_string => begin
        String(match(r"#([=]+)((.|\n)*)(\1)#", m.view)[2])
    end

    :string => begin
        @show ":string" m.view v typeof(v[1])
        v[1]
    end

    :prop => (v[1], v[5])

    :node_children => begin
        ret = Dict()
        for node in v[3]
            s, a, b = node
            merge!(ret, Dict(s => KDLNode(a, b)))
        end
        ret
    end

    :arg => v[1] isa Tuple ? v[1] : v[1], missing

    :node_args => begin
        args = Dict()
        for elem in v
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
        (v[1], v[3], v[5])
    end

    :node_only_params => begin
        (v[1], v[3], missing)
    end

    :node_only_children => begin
        (v[1], missing, v[3])
    end

    :node  => begin
        ret = @match v[1] begin
            (s, args, body) => (s, args,    body)
             s :: Symbol    => (s, missing, missing)
            _ => error("Weird node: $(v[1])")
        end
        ret
    end

    :slashdash => missing

    :knode => v[1]

    :kdl => begin
        ret = KDLNode()
        for node in v[2]
            s, a, b = node
            merge!(ret, Dict(s => KDLNode(a, b)))
        end
        ret
    end
end

function kdl_sparse(s)
    replace(s,
        raw"\n" => "\n", raw"\r" => "\r", raw"\t" => "\t",
        raw"\\" => "\\", raw"\"" => "\"", raw"\b" => "\b",
        raw"\f" => "\f",
    ) |> String
end

function kdl_desparse(s)
    replace(s,
        "\n" => raw"\n", "\r" => raw"\r", "\t" => raw"\t",
        "\\" => raw"\\", "\"" => raw"\"", "\b" => raw"\b",
        "\f" => raw"\f",
    ) |> String
end

function kdl_repr(v)
    v == Inf      ? "#inf"                    :
    v == -Inf     ? "#-inf"                   :
    v == NaN      ? "#nan"                    :
    v == true     ? "#true"                   :
    v == false    ? "#false"                  :
    v isa KDLNode ? prod(kdl_show(v) .* "\n") :
    v isa String  ? "\"$(kdl_desparse(v))\""  :
    v isa Symbol  ? repr(v)[2:end]            :
    isnothing(v)  ? "#null"                   :
                    v
end

function kdl_show(k::KDLNode; toplevel=false)
    s = IOBuffer()
    if !ismissing(k.a)
        for (k, v) in k.a
            if ismissing(v)
                print(s, kdl_repr(k), " ")
            else
                print(s, kdl_repr(k), "=", kdl_repr(v), " ")
            end
        end
    end
    if !ismissing(k.d)
        toplevel || println(s, "{")
        for (k, v) in k.d
            if ismissing(v)
                println(s, kdl_repr(k))
            else
                println(s, kdl_repr(k), " ", kdl_repr(v))
            end
        end
        toplevel || print(s, "}")
    end
    lines = filter(split(String(take!(s)), '\n')) do line
        !isnothing(match(r"[^\s]+", line)) && line != ""
    end
    length(lines) > 1 && for i=2:length(lines)-1
        lines[i] = "    " * lines[i]
    end
    return lines
end

function Base.show(io::IO, k::KDLNode)
    
    lines = kdl_show(k; toplevel=true)
    length(lines) == 0 && return
    println(io, lines[1])
    length(lines) == 1 && return
    for line in lines[2:end-1]
        io isa IOBuffer && print(io, "\t")
        println(io, line)
    end
    println(io, lines[end])
end

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

Base.empty!(k::KDLNode) = begin
    empty!(k.d)
    empty!(k.a)
end
Base.getindex(k :: KDLNode, i) = k.d[i]
function Base.getindex(k :: KDLNode, i :: Union{Vector,Tuple}) 
    length(i) == 0      && error("Zero-length index for $k")
    length(i) == 1      && return k[i[1]]
    k[i[1]] isa KDLNode && return k[i[1]][i[2:end]]
    return k[i]
end
Base.getindex(k :: KDLNode, i...)   = k[i]
Base.haskey(k :: KDLNode, i)        = haskey(k.d, i) || i in k()
Base.setindex!(k :: KDLNode, i,  v) = k.d[i] = v
function Base.setindex!(
    k :: KDLNode,
    i :: Union{Vector,Tuple},
    v) 

    length(i) == 0      && error("Zero-length index for $k")
    length(i) == 1      && return setindex!(k, i[1], v)
    k[i[1]] isa KDLNode && return setindex!(k[i[1]], i[2:end], v)
    k[i] = v
    nothing
end

function (k::KDLNode)()
    keys(k.a) |> Tuple
end

(k::KDLNode)(i)   = k.a[i]
(k::KDLNode)(i,n) = k.a[i] = n

⇜(k::KDLNode, i) = !ismissing(k[i]) 
←(k::KDLNode, i) = ismissing(k[i])

end # module KDL
