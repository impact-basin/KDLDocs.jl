semantics = P.@semantics :kdl m v begin

    :unicode_space => nothing
    :newline       => nothing
    :ws            => nothing

    :boolean => @match m.view begin
        "#true"  => true
        "#false" => false
    end

    :keywordnumber => @match m.view begin
        "#inf"  => Inf
        "#-inf" => -Inf
        "#nan"  => NaN
    end

    :keyword => begin
        !isnothing(v)     && return v[1]
        m.view == "#null" && return nothing
    end

    :sign => @match m.view begin
        "-" => -1
        "+" =>  1
        _   =>  1
    end

    :exponent =>
        m.view == "" ? nothing :
                       v[1].second[2] *
                       v[1].second[3]

    :decpart =>
        m.view == "" ? nothing :
            v[1].second[2] *
                10^(-ceil(log10(v[1].second[2])))

    :integer => parse(Int, m.view)
    :hex     => parse(Int, m.view)
    :octal   => parse(Int, m.view)
    :binary  => parse(Int, m.view)
    :number  => v[1]

    :decimal => begin
        x = v[1] * v[2]
        !isnothing(v[3]) && (x += v[3])
        !isnothing(v[4]) && (x *= 10^v[4])
        x
    end



    :singleline_string => kdl_sparse(m.view[2:end-1])
    :multiline_string  => kdl_sparse(m.view[4:end-3])
    :raw_string => String(
        match(r"#([=]+)((.|\n)*)(\1)#", m.view)[2]
    )

    :string => v[1]
    :ident  => Symbol(m.view)
    :sident => v[1]
    :type   => KDLNode(:type => v[3])
    :value  => v[2].second[1]
    :prop   => (v[1], v[5])

    :node_children => begin
        ret = OrderedDict()
        for node in v[3].second
            s, a, b = node
            ret[s] = KDLNode(a, b)
        end
        ret
    end

    :arg  => v[1] isa Tuple ? v[1] : v[1], missing
    :args => map(v) do item
        item.second[1]
    end

    :node_args => begin
        args = OrderedDict()
        for elem in v[1]
            @match elem begin
                (k, v) => begin
                    args[k] = v
                end
                k => begin
                    args[k] = missing
                end
            end
        end
        length(args) > 0 ? args : missing
    end

    :node      => (v[1], v[3], v[5])
    :slashdash => missing

    :kdlnode   => begin
        v[1]
    end

    :node_end  =>
        (v != []) && (v[1] isa OrderedDict) ? v[1] : missing

    :kdl => begin
        ret = KDLNode()
        for node in v[2].second
            s, a, b = node
            ret[s] = KDLNode(a, b)
        end
        ret
    end
end
