
"""
    add_self_loops(g::GNNGraph)

Return a graph with the same features as `g`
but also adding edges connecting the nodes to themselves.

Nodes with already existing self-loops will obtain a second self-loop.

If the graphs has edge weights, the new edges will have weight 1.
"""
function add_self_loops(g::GNNGraph{<:COO_T})
    s, t = edge_index(g)
    @assert g.edata === (;)
    ew = get_edge_weight(g)
    n = g.num_nodes
    nodes = convert(typeof(s), [1:n;])
    s = [s; nodes]
    t = [t; nodes]
    if ew !== nothing
        ew = [ew; fill!(similar(ew, n), 1)]
    end

    GNNGraph((s, t, ew), 
        g.num_nodes, length(s), g.num_graphs, 
        g.graph_indicator,
        g.ndata, g.edata, g.gdata)
end

function add_self_loops(g::GNNGraph{<:ADJMAT_T})
    A = g.graph
    @assert g.edata === (;)
    num_edges = g.num_edges + g.num_nodes
    A = A + I
    GNNGraph(A, 
            g.num_nodes, num_edges, g.num_graphs, 
            g.graph_indicator,
            g.ndata, g.edata, g.gdata)
end

"""
    remove_self_loops(g::GNNGraph)

Return a graph constructed from `g` where self-loops (edges from a node to itself)
are removed. 

See also [`add_self_loops`](@ref) and [`remove_multi_edges`](@ref).
"""
function remove_self_loops(g::GNNGraph{<:COO_T})
    s, t = edge_index(g)
    w = get_edge_weight(g)
    edata = g.edata
    
    mask_old_loops = s .!= t
    s = s[mask_old_loops]
    t = t[mask_old_loops]
    edata = getobs(edata, mask_old_loops)
    w = isnothing(w) ? nothing : getobs(w, mask_old_loops)
    
    GNNGraph((s, t, w), 
            g.num_nodes, length(s), g.num_graphs, 
            g.graph_indicator,
            g.ndata, edata, g.gdata)
end


function remove_self_loops(g::GNNGraph{<:ADJMAT_T})
    @assert g.edata === (;)
    A = g.graph
    A[diagind(A)] .= 0
    if A isa AbstractSparseMatrix
        dropzeros!(A)
    end
    num_edges = numnonzeros(A)
    GNNGraph(A, 
            g.num_nodes, num_edges, g.num_graphs, 
            g.graph_indicator,
            g.ndata, g.edata, g.gdata)
end


"""
    remove_multi_edges(g::GNNGraph; aggr=+)

Remove multiple edges (also called parallel edges or repeated edges) from graph `g`.
Possible edge features are aggregated according to `aggr`, that can take value 
`+`,`min`, `max` or `mean`.

See also [`remove_self_loops`](@ref), [`has_multi_edges`](@ref), and [`to_bidirected`](@ref).
"""
function remove_multi_edges(g::GNNGraph{<:COO_T}; aggr=+)
    s, t = edge_index(g)
    w = get_edge_weight(g)
    edata = g.edata
    num_edges = g.num_edges
    
    idxs, idxmax = edge_encoding(s, t, g.num_nodes)
    
    perm = sortperm(idxs)
    idxs = idxs[perm]
    s, t = s[perm], t[perm]
    edata = getobs(edata, perm)
    w = isnothing(w) ? nothing : getobs(w, perm)
    idxs = [-1; idxs]
    mask = idxs[2:end] .> idxs[1:end-1]
    if !all(mask)
        s, t = s[mask], t[mask]
        idxs = similar(s, num_edges)
        idxs .= 1:num_edges
        idxs .= idxs .- cumsum(.!mask)
        num_edges = length(s)
        w = _scatter(aggr, w, idxs, num_edges)
        edata = _scatter(aggr, edata, idxs, num_edges)
    end

    GNNGraph((s, t, w),
            g.num_nodes, num_edges, g.num_graphs,
            g.graph_indicator,
            g.ndata, edata, g.gdata)
end

"""
    add_edges(g::GNNGraph, s::AbstractVector, t::AbstractVector; [edata])

Add to graph `g` the edges with source nodes `s` and target nodes `t`.
Optionally, pass the features  `edata` for the new edges. 
"""
function add_edges(g::GNNGraph{<:COO_T}, 
                snew::AbstractVector{<:Integer}, 
                tnew::AbstractVector{<:Integer};
                edata=nothing)

    @assert length(snew) == length(tnew)
    # TODO remove this constraint
    @assert get_edge_weight(g) === nothing

    edata = normalize_graphdata(edata, default_name=:e, n=length(snew))
    edata = cat_features(g.edata, edata)
    
    s, t = edge_index(g)
    s = [s; snew]
    t = [t; tnew]

    GNNGraph((s, t, nothing), 
            g.num_nodes, length(s), g.num_graphs, 
            g.graph_indicator,
            g.ndata, edata, g.gdata)
end

### TODO Cannot implement this since GNNGraph is immutable (cannot change num_edges)
# function Graphs.add_edge!(g::GNNGraph{<:COO_T}, snew::T, tnew::T; edata=nothing) where T<:Union{Integer, AbstractVector}
#     s, t = edge_index(g)
#     @assert length(snew) == length(tnew)
#     # TODO remove this constraint
#     @assert get_edge_weight(g) === nothing
    
#     edata = normalize_graphdata(edata, default_name=:e, n=length(snew))
#     edata = cat_features(g.edata, edata)
    
#     s, t = edge_index(g)
#     append!(s, snew)
#     append!(t, tnew)
#     g.num_edges += length(snew)
#     return true
# end

"""
    to_bidirected(g)

Adds a reverse edge for each edge in the graph, then calls 
[`remove_multi_edges`](@ref) with `mean` aggregation to simplify the graph. 

See also [`is_bidirected`](@ref). 

# Examples

```juliarepl
julia> s, t = [1, 2, 3, 3, 4], [2, 3, 4, 4, 4];

julia> w = [1.0, 2.0, 3.0, 4.0, 5.0];

julia> e = [10.0, 20.0, 30.0, 40.0, 50.0];

julia> g = GNNGraph(s, t, w, edata = e)
GNNGraph:
    num_nodes = 4
    num_edges = 5
    edata:
        e => (5,)

julia> g2 = to_bidirected(g)
GNNGraph:
    num_nodes = 4
    num_edges = 7
    edata:
        e => (7,)

julia> edge_index(g2)
([1, 2, 2, 3, 3, 4, 4], [2, 1, 3, 2, 4, 3, 4])

julia> get_edge_weight(g2)
7-element Vector{Float64}:
 1.0
 1.0
 2.0
 2.0
 3.5
 3.5
 5.0

julia> g2.edata.e
7-element Vector{Float64}:
 10.0
 10.0
 20.0
 20.0
 35.0
 35.0
 50.0
```
"""
function to_bidirected(g::GNNGraph{<:COO_T})
    s, t = edge_index(g)
    w = get_edge_weight(g)
    snew = [s; t]
    tnew = [t; s] 
    w = cat_features(w, w)
    edata = cat_features(g.edata, g.edata)   

    g = GNNGraph((snew, tnew, w),
                g.num_nodes, length(snew), g.num_graphs,
                g.graph_indicator,
                g.ndata, edata, g.gdata)

    return remove_multi_edges(g; aggr=mean)
end

"""
    to_unidirected(g::GNNGraph)

Return a graph that for each multiple edge between two nodes in `g`
keeps only an edge in one direction.
"""
function to_unidirected(g::GNNGraph{<:COO_T})
    s, t = edge_index(g)
    w = get_edge_weight(g)
    idxs, _ = edge_encoding(s, t, g.num_nodes, directed=false)
    snew, tnew = edge_decoding(idxs, g.num_nodes, directed=false)

    g = GNNGraph((snew, tnew, w),
                g.num_nodes, g.num_edges, g.num_graphs,
                g.graph_indicator,
                g.ndata, g.edata, g.gdata)

    return remove_multi_edges(g; aggr=mean)
end

function Graphs.SimpleGraph(g::GNNGraph)
    G = Graphs.SimpleGraph(g.num_nodes)
    for e in Graphs.edges(g)
        Graphs.add_edge!(G, e)
    end
    return G
end
function Graphs.SimpleDiGraph(g::GNNGraph)
    G = Graphs.SimpleDiGraph(g.num_nodes)
    for e in Graphs.edges(g)
        Graphs.add_edge!(G, e)
    end
    return G
end


"""
    add_nodes(g::GNNGraph, n; [ndata])

Add `n` new nodes to graph `g`. In the 
new graph, these nodes will have indexes from `g.num_nodes + 1`
to `g.num_nodes + n`.
"""
function add_nodes(g::GNNGraph{<:COO_T}, n::Integer; ndata=(;))
    ndata = normalize_graphdata(ndata, default_name=:x, n=n)
    ndata = cat_features(g.ndata, ndata)

    GNNGraph(g.graph, 
            g.num_nodes + n, g.num_edges, g.num_graphs, 
            g.graph_indicator,
            ndata, g.edata, g.gdata)
end

"""
    set_edge_weight(g::GNNGraph, w::AbstractVector)

Set `w` as edge weights in the returned graph. 
"""
function set_edge_weight(g::GNNGraph, w::AbstractVector)
    s, t = edge_index(g)
    @assert length(w) == length(s)

    return GNNGraph((s, t, w), 
                    g.num_nodes, g.num_edges, g.num_graphs, 
                    g.graph_indicator,
                    g.ndata, g.edata, g.gdata)
end

function SparseArrays.blockdiag(g1::GNNGraph, g2::GNNGraph)
    nv1, nv2 = g1.num_nodes, g2.num_nodes
    if g1.graph isa COO_T
        s1, t1 = edge_index(g1)
        s2, t2 = edge_index(g2)
        s = vcat(s1, nv1 .+ s2)
        t = vcat(t1, nv1 .+ t2)
        w = cat_features(get_edge_weight(g1), get_edge_weight(g2))
        graph = (s, t, w)
        ind1 = isnothing(g1.graph_indicator) ? ones_like(s1, nv1) : g1.graph_indicator 
        ind2 = isnothing(g2.graph_indicator) ? ones_like(s2, nv2) : g2.graph_indicator     
    elseif g1.graph isa ADJMAT_T        
        graph = blockdiag(g1.graph, g2.graph)
        ind1 = isnothing(g1.graph_indicator) ? ones_like(graph, nv1) : g1.graph_indicator 
        ind2 = isnothing(g2.graph_indicator) ? ones_like(graph, nv2) : g2.graph_indicator     
    end
    graph_indicator = vcat(ind1, g1.num_graphs .+ ind2)
    
    GNNGraph(graph,
            nv1 + nv2, g1.num_edges + g2.num_edges, g1.num_graphs + g2.num_graphs, 
            graph_indicator,
            cat_features(g1.ndata, g2.ndata),
            cat_features(g1.edata, g2.edata),
            cat_features(g1.gdata, g2.gdata))
end

# PIRACY
function SparseArrays.blockdiag(A1::AbstractMatrix, A2::AbstractMatrix)
    m1, n1 = size(A1)
    @assert m1 == n1
    m2, n2 = size(A2)
    @assert m2 == n2
    O1 = fill!(similar(A1, eltype(A1), (m1, n2)), 0)
    O2 = fill!(similar(A1, eltype(A1), (m2, n1)), 0)
    return [A1 O1
            O2 A2]
end

"""
    blockdiag(xs::GNNGraph...)

Equivalent to [`Flux.batch`](@ref).
"""
function SparseArrays.blockdiag(g1::GNNGraph, gothers::GNNGraph...)
    g = g1
    for go in gothers
        g = blockdiag(g, go)
    end
    return g
end

"""
    batch(gs::Vector{<:GNNGraph})

Batch together multiple `GNNGraph`s into a single one 
containing the total number of original nodes and edges.

Equivalent to [`SparseArrays.blockdiag`](@ref).
See also [`Flux.unbatch`](@ref).

# Examples

```juliarepl
julia> g1 = rand_graph(4, 6, ndata=ones(8, 4))
GNNGraph:
    num_nodes = 4
    num_edges = 6
    ndata:
        x => (8, 4)

julia> g2 = rand_graph(7, 4, ndata=zeros(8, 7))
GNNGraph:
    num_nodes = 7
    num_edges = 4
    ndata:
        x => (8, 7)

julia> g12 = Flux.batch([g1, g2])
GNNGraph:
    num_nodes = 11
    num_edges = 10
    num_graphs = 2
    ndata:
        x => (8, 11)

julia> g12.ndata.x
8×11 Matrix{Float64}:
 1.0  1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 1.0  1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 1.0  1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 1.0  1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 1.0  1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 1.0  1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 1.0  1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 1.0  1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
```
"""
Flux.batch(gs::AbstractVector{<:GNNGraph}) = blockdiag(gs...)

function Flux.batch(gs::AbstractVector{<:GNNGraph{T}}) where T<:COO_T
    v_num_nodes = [g.num_nodes for g in gs]
    edge_indices = [edge_index(g) for g in gs]
    nodesum = cumsum([0; v_num_nodes])[1:end-1]
    s = cat_features([ei[1] .+ nodesum[ii] for (ii, ei) in enumerate(edge_indices)])
    t = cat_features([ei[2] .+ nodesum[ii] for (ii, ei) in enumerate(edge_indices)])
    w = cat_features([get_edge_weight(g) for g in gs])
    graph = (s, t, w)

    function materialize_graph_indicator(g)
        g.graph_indicator === nothing ? ones_like(s, g.num_nodes) : g.graph_indicator
    end

    v_gi = materialize_graph_indicator.(gs)
    v_num_graphs = [g.num_graphs for g in gs]
    graphsum = cumsum([0; v_num_graphs])[1:end-1]
    v_gi = [ng .+ gi  for (ng, gi) in zip(graphsum, v_gi)]
    graph_indicator = cat_features(v_gi)
    
    GNNGraph(graph,
        sum(v_num_nodes), 
        sum([g.num_edges for g in gs]),
        sum(v_num_graphs),
        graph_indicator,
        cat_features([g.ndata for g in gs]),
        cat_features([g.edata for g in gs]),
        cat_features([g.gdata for g in gs]),
    )
end

"""
    unbatch(g::GNNGraph)

Opposite of the [`Flux.batch`](@ref) operation, returns 
an array of the individual graphs batched together in `g`.

See also [`Flux.batch`](@ref) and [`getgraph`](@ref).

# Examples

```juliarepl
julia> gbatched = Flux.batch([rand_graph(5, 6), rand_graph(10, 8), rand_graph(4,2)])
GNNGraph:
    num_nodes = 19
    num_edges = 16
    num_graphs = 3

julia> Flux.unbatch(gbatched)
3-element Vector{GNNGraph{Tuple{Vector{Int64}, Vector{Int64}, Nothing}}}:
 GNNGraph:
    num_nodes = 5
    num_edges = 6

 GNNGraph:
    num_nodes = 10
    num_edges = 8

 GNNGraph:
    num_nodes = 4
    num_edges = 2
```
"""
function Flux.unbatch(g::GNNGraph) 
    [getgraph(g, i) for i in 1:g.num_graphs]
end


"""
    getgraph(g::GNNGraph, i; nmap=false)

Return the subgraph of `g` induced by those nodes `j`
for which `g.graph_indicator[j] == i` or,
if `i` is a collection, `g.graph_indicator[j] ∈ i`. 
In other words, it extract the component graphs from a batched graph. 

If `nmap=true`, return also a vector `v` mapping the new nodes to the old ones. 
The node `i` in the subgraph will correspond to the node `v[i]` in `g`.
"""
getgraph(g::GNNGraph, i::Int; kws...) = getgraph(g, [i]; kws...)

function getgraph(g::GNNGraph, i::AbstractVector{Int}; nmap=false)
    if g.graph_indicator === nothing
        @assert i == [1]
        if nmap
            return g, 1:g.num_nodes
        else
            return g
        end
    end

    node_mask = g.graph_indicator .∈ Ref(i)
    
    nodes = (1:g.num_nodes)[node_mask]
    nodemap = Dict(v => vnew for (vnew, v) in enumerate(nodes))

    graphmap = Dict(i => inew for (inew, i) in enumerate(i))
    graph_indicator = [graphmap[i] for i in g.graph_indicator[node_mask]]
    
    s, t = edge_index(g)
    w = get_edge_weight(g)
    edge_mask = s .∈ Ref(nodes) 
    
    if g.graph isa COO_T 
        s = [nodemap[i] for i in s[edge_mask]]
        t = [nodemap[i] for i in t[edge_mask]]
        w = isnothing(w) ? nothing : w[edge_mask]
        graph = (s, t, w)
    elseif g.graph isa ADJMAT_T
        graph = g.graph[nodes, nodes]
    end

    ndata = getobs(g.ndata, node_mask)
    edata = getobs(g.edata, edge_mask)
    gdata = getobs(g.gdata, i)
    
    num_edges = sum(edge_mask)
    num_nodes = length(graph_indicator)
    num_graphs = length(i)

    gnew = GNNGraph(graph, 
                num_nodes, num_edges, num_graphs,
                graph_indicator,
                ndata, edata, gdata)

    if nmap
        return gnew, nodes
    else
        return gnew
    end
end

"""
    negative_sample(g::GNNGraph; 
                    num_neg_edges = g.num_edges, 
                    bidirected = is_bidirected(g))

Return a graph containing random negative edges (i.e. non-edges) from graph `g` as edges.

If `bidirected=true`, the output graph will be bidirected and there will be no
leakage from the origin graph. 

See also [`is_bidirected`](@ref).
"""
function negative_sample(g::GNNGraph; 
        max_trials=3, 
        num_neg_edges=g.num_edges, 
        bidirected = is_bidirected(g))

    @assert g.num_graphs == 1
    # Consider self-loops as positive edges
    # Construct new graph dropping features
    g = add_self_loops(GNNGraph(edge_index(g), num_nodes=g.num_nodes)) 
    
    s, t = edge_index(g)
    n = g.num_nodes
    if s isa CuArray
        # Convert to gpu since set operations and sampling are not supported by CUDA.jl
        device = Flux.gpu 
        s, t = Flux.cpu(s), Flux.cpu(t) 
    else 
        device = Flux.cpu
    end
    idx_pos, maxid = edge_encoding(s, t, n)
    if bidirected
        num_neg_edges = num_neg_edges ÷ 2
        pneg = 1 - g.num_edges / 2maxid # prob of selecting negative edge 
    else 
        pneg = 1 - g.num_edges / 2maxid # prob of selecting negative edge 
    end    
    # pneg * sample_prob * maxid == num_neg_edges  
    sample_prob = min(1, num_neg_edges / (pneg * maxid) * 1.1)
    idx_neg = Int[]
    for _ in 1:max_trials
        rnd = randsubseq(1:maxid, sample_prob)
        setdiff!(rnd, idx_pos)
        union!(idx_neg, rnd)
        if length(idx_neg) >= num_neg_edges
            idx_neg = idx_neg[1:num_neg_edges]
            break
        end
    end
    s_neg, t_neg = edge_decoding(idx_neg, n)
    if bidirected
        s_neg, t_neg = [s_neg; t_neg], [t_neg; s_neg] 
    end
    return GNNGraph(s_neg, t_neg, num_nodes=n) |> device
end

"""
    rand_edge_split(g::GNNGraph, frac; bidirected=is_bidirected(g)) -> g1, g2

Randomly partition the edges in `g` to form two graphs, `g1`
and `g2`. Both will have the same number of nodes as `g`.
`g1` will contain a fraction `frac` of the original edges, 
while `g2` wil contain the rest.

If `bidirected = true` makes sure that an edge and its reverse go into the same split.
This option is supported only for bidirected graphs with no self-loops
and multi-edges.

`rand_edge_split` is tipically used to create train/test splits in link prediction tasks.
"""
function rand_edge_split(g::GNNGraph, frac; bidirected=is_bidirected(g))
    s, t = edge_index(g)
    ne = bidirected ? g.num_edges ÷ 2 : g.num_edges
    eids = randperm(ne)
    size1 = round(Int, ne * frac)
    
    if !bidirected
        s1, t1 = s[eids[1:size1]], t[eids[1:size1]]
        s2, t2 = s[eids[size1+1:end]], t[eids[size1+1:end]]
    else
        # @assert is_bidirected(g)
        # @assert !has_self_loops(g)
        # @assert !has_multi_edges(g)
        mask = s .< t
        s, t = s[mask], t[mask]
        s1, t1 = s[eids[1:size1]], t[eids[1:size1]]
        s1, t1 = [s1; t1], [t1; s1]
        s2, t2 = s[eids[size1+1:end]], t[eids[size1+1:end]]
        s2, t2 = [s2; t2], [t2; s2]
    end
    g1 = GNNGraph(s1, t1, num_nodes=g.num_nodes)
    g2 = GNNGraph(s2, t2, num_nodes=g.num_nodes)
    return g1, g2
end


# """
# Transform vector of cartesian indexes into a tuple of vectors containing integers.
# """
ci2t(ci::AbstractVector{<:CartesianIndex}, dims) = ntuple(i -> map(x -> x[i], ci), dims)

@non_differentiable negative_sample(x...)
@non_differentiable add_self_loops(x...)     # TODO this is wrong, since g carries feature arrays, needs rrule
@non_differentiable remove_self_loops(x...)  # TODO this is wrong, since g carries feature arrays, needs rrule
