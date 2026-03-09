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

function kdl_format_string(s)
    ds = kdl_desparse(s)
    '"'  in ds ? "#=$ds=#"            :
    '\n' in ds ? "\""^3 * ds * "\""^3 :
                 "\"$ds\""
end

function kdl_format_number(s::Number)
    s ==  NaN ? styled"#nan"  :
    s ==  Inf ? styled"#inf"  :
    s == -Inf ? styled"#-inf" : styled"$(repr(s))"
end

function kdl_repr(v)
    @match v begin
        k::KDLNode => kdl_show(k, false)
        b::Bool    => styled"{bright_blue:#$(repr(b))}"
        f::Number  => styled"{bright_red:$(kdl_format_number(f))}"
        s::String  => styled"{bright_red:$(kdl_format_string(s))}"
        s::Symbol  => styled"$(repr(s)[2:end])"
        nothing    => styled"{gray:#null}"
    end
end

kdl_nodename(k) = styled"{cyan:$k}"

node_args(::Missing) = styled""
node_body(::Missing) = styled""

indent(s) = replace(s, styled"\n" => styled"\n\t")

node_args(d::OrderedDict) = length(d) > 0 ?
        [node_args(k,v) for (k,v) in d] |> prod : ""

function node_body(d::OrderedDict, top = false)
    length(d) == 0 && return styled""
    #=@info "node_body()" typeof(d)=#
    body = join([node_body(k,v) for (k,v) in d], styled"\n")
    top && return body
    return "{" * indent("\n" * body) * "\n}\n"
end

node_args(::Missing, _) = ""
node_args(k, ::Missing) = kdl_repr(k) * " "
node_args(k, v) = kdl_repr(k) * "=" * kdl_repr(v) * " "  

node_body(::Missing, _) = ""
node_body(k, ::Missing) = kdl_nodename(k) * " "
node_body(k, v)         = kdl_nodename(k) * " " * kdl_repr(v) * " "

function kdl_show(k::KDLNode, top=false) 
    a = node_args(k.args) 
    b = node_body(k.body, top)
    return a * b
    return repr(k.args) * "\n" * repr(k.body)
end

Base.show(io::IO, k::KDLNode)       = println(io, kdl_show(k, true))
Base.write(s::IOStream, k::KDLNode) = write(s, kdl_show(k))
kdl(s::IOStream)                    = kdl(read(s, String))

kdl_read(s::String) = open(s, "r") do f
    read(f, String) |> kdl
end

macro kdl_str(s)
    k = kdl(s); quote $k end
end
