const NODE_ID = Union{Symbol, String}

struct KDLNode
    args :: Union{OrderedDict, Missing}
    body :: Union{OrderedDict, Missing}

    KDLNode(body::Pair...)                        = new(OrderedDict(), OrderedDict(body))
    KDLNode()                                     = new(OrderedDict(), OrderedDict())
    KDLNode(_::Missing,        _::Missing)        = new(missing, missing)
    KDLNode(args::OrderedDict, body::OrderedDict) = new(args, body)
    KDLNode(args::OrderedDict, body::Missing)     = new(args, body)
    KDLNode(args::Missing,     body::OrderedDict) = new(args, body)
end

(k::KDLNode)()    = keys(k.args) |> Tuple
(k::KDLNode)(i)   = k.args[i]
(k::KDLNode)(i,n) = k.args[i] = n

Base.empty!(k::KDLNode) = begin
    empty!(k.args)
    empty!(k.body)
end

Base.getindex(k :: KDLNode, i) = k.body[i]
function Base.getindex(k :: KDLNode, i :: Union{Vector,Tuple}) 
    length(i) == 0      && error("Zero-length index for $k")
    length(i) == 1      && return k[i[1]]
    k[i[1]] isa KDLNode && return k[i[1]][i[2:end]]
    return k[i]
end
Base.getindex(k :: KDLNode, i...)   = k[i]
Base.getindex(k :: KDLNode)         = keys(k.body)
Base.haskey(k :: KDLNode, i)        = haskey(k.body, i) || i in k()
Base.setindex!(k :: KDLNode, i,  v) = k.body[v] = i

function Base.setindex!(
    k :: KDLNode,
    i :: Union{Vector,Tuple},
    v) 

    length(i) == 0      && error("Zero-length index for $k")
    length(i) == 1      && return setindex!(k, v, i[1])
    k[i[1]] isa KDLNode && return setindex!(k[i[1]], v, i[2:end])
    k[i] = v
    nothing
end

Base.merge(j::KDLNode, k::KDLNode) =
    KDLNode(merge(j.args, k.args),
            merge(j.body, k.body))

Base.merge!(j::KDLNode, k::KDLNode) = j = merge(j, k)
