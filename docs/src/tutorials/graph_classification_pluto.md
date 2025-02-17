```@meta
EditURL = "/home/carlo/.julia/dev/GraphNeuralNetworks/docs/src/tutorials/graph_classification_pluto.jl"
```
```@raw html
<style>
    table {
        display: table !important;
        margin: 2rem auto !important;
        border-top: 2pt solid rgba(0,0,0,0.2);
        border-bottom: 2pt solid rgba(0,0,0,0.2);
    }

    pre, div {
        margin-top: 1.4rem !important;
        margin-bottom: 1.4rem !important;
    }

    .code-output {
        padding: 0.7rem 0.5rem !important;
    }

    .admonition-body {
        padding: 0em 1.25em !important;
    }
</style>

<!-- PlutoStaticHTML.Begin -->
<!--
    # This information is used for caching.
    [PlutoStaticHTML.State]
    input_sha = "4c39840ec83c85e11eb7ee5a181b66c85e85774597e21aa897d0391f3d22d4fa"
    julia_version = "1.7.2"
-->
<pre class='language-julia'><code class='language-julia'>begin
    using Flux
    using Flux: onecold, onehotbatch, logitcrossentropy
    using GraphNeuralNetworks
    using MLDatasets
    using LinearAlgebra, Random, Statistics
    Random.seed!(17)
end;</code></pre>



<div class="markdown"><h1>Graph Classification with Graph Neural Networks</h1>
<p>In this tutorial session we will have a closer look at how to apply <strong>Graph Neural Networks &#40;GNNs&#41; to the task of graph classification</strong>. Graph classification refers to the problem of classifiying entire graphs &#40;in contrast to nodes&#41;, given a <strong>dataset of graphs</strong>, based on some structural graph properties. Here, we want to embed entire graphs, and we want to embed those graphs in such a way so that they are linearly separable given a task at hand.</p>
<p>The most common task for graph classification is <strong>molecular property prediction</strong>, in which molecules are represented as graphs, and the task may be to infer whether a molecule inhibits HIV virus replication or not.</p>
<p>The TU Dortmund University has collected a wide range of different graph classification datasets, known as the <a href="https://chrsmrrs.github.io/datasets/"><strong>TUDatasets</strong></a>, which are also accessible via MLDatasets.jl. Let&#39;s load and inspect one of the smaller ones, the <strong>MUTAG dataset</strong>:</p>
</div>

<pre class='language-julia'><code class='language-julia'>dataset = TUDataset("MUTAG")</code></pre>
<pre id='var-dataset' class='code-output documenter-example-output'>dataset TUDataset:
  name        =>    MUTAG
  metadata    =>    Dict{String, Any} with 1 entry
  graphs      =>    188-element Vector{MLDatasets.Graph}
  graph_data  =>    (targets = "188-element Vector{Int64}",)
  num_nodes   =>    3371
  num_edges   =>    7442
  num_graphs  =>    188</pre>

<pre class='language-julia'><code class='language-julia'>dataset.graph_data.targets |&gt; union</code></pre>
<pre id='var-hash194771' class='code-output documenter-example-output'>2-element Vector{Int64}:
  1
 -1</pre>

<pre class='language-julia'><code class='language-julia'>g1, y1  = dataset[1] #get the first graph and target</code></pre>
<pre id='var-y1' class='code-output documenter-example-output'>(graphs = Graph(17, 38), targets = 1)</pre>

<pre class='language-julia'><code class='language-julia'>reduce(vcat, g.node_data.targets for (g,_) in dataset) |&gt; union</code></pre>
<pre id='var-hash163982' class='code-output documenter-example-output'>7-element Vector{Int64}:
 0
 1
 2
 3
 4
 5
 6</pre>

<pre class='language-julia'><code class='language-julia'>reduce(vcat, g.edge_data.targets for (g,_) in dataset)|&gt; union</code></pre>
<pre id='var-hash766940' class='code-output documenter-example-output'>4-element Vector{Int64}:
 0
 1
 2
 3</pre>


<div class="markdown"><p>This dataset provides <strong>188 different graphs</strong>, and the task is to classify each graph into <strong>one out of two classes</strong>.</p>
<p>By inspecting the first graph object of the dataset, we can see that it comes with <strong>17 nodes</strong> and <strong>38 edges</strong>. It also comes with exactly <strong>one graph label</strong>, and provides additional node labels &#40;7 classes&#41; and edge labels &#40;4 classes&#41;. However, for the sake of simplicity, we will not make use of edge labels.</p>
<p>We have some useful utilities for working with graph datasets, <em>e.g.</em>, we can shuffle the dataset and use the first 150 graphs as training graphs, while using the remaining ones for testing:</p>
</div>

<pre class='language-julia'><code class='language-julia'>begin
    graphs = mldataset2gnngraph(dataset)
    graphs = [GNNGraph(g, 
                       ndata=Float32.(onehotbatch(g.ndata.targets, 0:6)),
                       edata=nothing) 
              for g in graphs]
end</code></pre>
<pre id='var-graphs' class='code-output documenter-example-output'>188-element Vector{GNNGraph{Tuple{Vector{Int64}, Vector{Int64}, Nothing}}}:
 GNNGraph(17, 38)
 GNNGraph(13, 28)
 GNNGraph(13, 28)
 GNNGraph(19, 44)
 GNNGraph(11, 22)
 GNNGraph(28, 62)
 GNNGraph(16, 34)
 ⋮
 GNNGraph(22, 50)
 GNNGraph(22, 50)
 GNNGraph(13, 26)
 GNNGraph(12, 26)
 GNNGraph(21, 48)
 GNNGraph(16, 36)</pre>

<pre class='language-julia'><code class='language-julia'>using MLUtils</code></pre>


<pre class='language-julia'><code class='language-julia'>begin
    shuffled_idxs = randperm(length(graphs))
    train_idxs = shuffled_idxs[1:150]
    test_idxs = shuffled_idxs[151:end]
    train_graphs = graphs[train_idxs]
    test_graphs = graphs[test_idxs]
    ytrain = onehotbatch(dataset.graph_data.targets[train_idxs], [-1, 1])
    ytest = onehotbatch(dataset.graph_data.targets[test_idxs], [-1, 1])
end</code></pre>
<pre id='var-train_idxs' class='code-output documenter-example-output'>2×38 OneHotMatrix(::Vector{UInt32}) with eltype Bool:
 ⋅  1  ⋅  1  ⋅  ⋅  ⋅  ⋅  ⋅  ⋅  ⋅  ⋅  1  ⋅  …  ⋅  ⋅  ⋅  ⋅  ⋅  ⋅  ⋅  ⋅  ⋅  ⋅  ⋅  1  ⋅
 1  ⋅  1  ⋅  1  1  1  1  1  1  1  1  ⋅  1     1  1  1  1  1  1  1  1  1  1  1  ⋅  1</pre>


<div class="markdown"><h2>Mini-batching of graphs</h2>
<p>Since graphs in graph classification datasets are usually small, a good idea is to <strong>batch the graphs</strong> before inputting them into a Graph Neural Network to guarantee full GPU utilization. In the image or language domain, this procedure is typically achieved by <strong>rescaling</strong> or <strong>padding</strong> each example into a set of equally-sized shapes, and examples are then grouped in an additional dimension. The length of this dimension is then equal to the number of examples grouped in a mini-batch and is typically referred to as the <code>batchsize</code>.</p>
<p>However, for GNNs the two approaches described above are either not feasible or may result in a lot of unnecessary memory consumption. Therefore, GNN.jl opts for another approach to achieve parallelization across a number of examples. Here, adjacency matrices are stacked in a diagonal fashion &#40;creating a giant graph that holds multiple isolated subgraphs&#41;, and node and target features are simply concatenated in the node dimension &#40;the last dimension&#41;.</p>
<p>This procedure has some crucial advantages over other batching procedures:</p>
<ol>
<li><p>GNN operators that rely on a message passing scheme do not need to be modified since messages are not exchanged between two nodes that belong to different graphs.</p>
</li>
<li><p>There is no computational or memory overhead since adjacency matrices are saved in a sparse fashion holding only non-zero entries, <em>i.e.</em>, the edges.</p>
</li>
</ol>
<p>GNN.jl can <strong>batch multiple graphs into a single giant graph</strong> with the help of Flux&#39;s <code>DataLoader</code>:</p>
</div>

<pre class='language-julia'><code class='language-julia'>begin
    train_loader = DataLoader((train_graphs, ytrain), batchsize=64, shuffle=true)
    test_loader = DataLoader((test_graphs, ytest), batchsize=64, shuffle=false)
end</code></pre>
<pre id='var-test_loader' class='code-output documenter-example-output'>DataLoader{Tuple{Vector{GNNGraph{Tuple{Vector{Int64}, Vector{Int64}, Nothing}}}, Flux.OneHotArray{UInt32, 2, 1, 2, Vector{UInt32}}}, Random._GLOBAL_RNG}((GNNGraph{Tuple{Vector{Int64}, Vector{Int64}, Nothing}}[GNNGraph(17, 38), GNNGraph(13, 28), GNNGraph(20, 44), GNNGraph(13, 28), GNNGraph(20, 46), GNNGraph(15, 34), GNNGraph(13, 28), GNNGraph(16, 34), GNNGraph(26, 60), GNNGraph(17, 38)  …  GNNGraph(22, 50), GNNGraph(23, 54), GNNGraph(23, 54), GNNGraph(23, 54), GNNGraph(15, 34), GNNGraph(12, 26), GNNGraph(26, 60), GNNGraph(20, 44), GNNGraph(13, 26), GNNGraph(19, 44)], Bool[0 1 … 1 0; 1 0 … 0 1]), 38, 38, true, false, Random._GLOBAL_RNG())</pre>

<pre class='language-julia'><code class='language-julia'>first(train_loader)</code></pre>
<pre id='var-hash113787' class='code-output documenter-example-output'>(GNNGraph(1137, 2516), Bool[1 1 … 1 0; 0 0 … 0 1])</pre>

<pre class='language-julia'><code class='language-julia'>collect(train_loader)</code></pre>
<pre id='var-hash151660' class='code-output documenter-example-output'>3-element Vector{Tuple{GNNGraph{Tuple{Vector{Int64}, Vector{Int64}, Nothing}}, Flux.OneHotArray{UInt32, 2, 1, 2, Vector{UInt32}}}}:
 (GNNGraph(1116, 2450), [0 0 … 1 0; 1 1 … 0 1])
 (GNNGraph(1159, 2574), [0 0 … 1 0; 1 1 … 0 1])
 (GNNGraph(419, 914), [1 0 … 0 0; 0 1 … 1 1])</pre>

<pre class='language-julia'><code class='language-julia'>first(train_loader)[1]</code></pre>
<pre id='var-hash134244' class='code-output documenter-example-output'>GNNGraph:
    num_nodes = 1187
    num_edges = 2626
    num_graphs = 64
    ndata:
        x => 7×1187 Matrix{Float32}</pre>


<div class="markdown"><p>Here, we opt for a <code>batch_size</code> of 64, leading to 3 &#40;randomly shuffled&#41; mini-batches, containing all <span class="tex">$2 \cdot 64&#43;22 &#61; 150$</span> graphs.</p>
<p>Furthermore, each batched graph object is equipped with a <strong><code>graph_indicator</code> vector</strong>, which maps each node to its respective graph in the batch:</p>
<p class="tex">$$\textrm&#123;graph-indicator&#125; &#61; &#91;1, \ldots, 1, 2, \ldots, 2, 3, \ldots &#93;$$</p>
<h2>Training a Graph Neural Network &#40;GNN&#41;</h2>
<p>Training a GNN for graph classification usually follows a simple recipe:</p>
<ol>
<li><p>Embed each node by performing multiple rounds of message passing</p>
</li>
<li><p>Aggregate node embeddings into a unified graph embedding &#40;<strong>readout layer</strong>&#41;</p>
</li>
<li><p>Train a final classifier on the graph embedding</p>
</li>
</ol>
<p>There exists multiple <strong>readout layers</strong> in literature, but the most common one is to simply take the average of node embeddings:</p>
<p class="tex">$$\mathbf&#123;x&#125;_&#123;\mathcal&#123;G&#125;&#125; &#61; \frac&#123;1&#125;&#123;|\mathcal&#123;V&#125;|&#125; \sum_&#123;v \in \mathcal&#123;V&#125;&#125; \mathcal&#123;x&#125;^&#123;&#40;L&#41;&#125;_v$$</p>
<p>GNN.jl provides this functionality via <code>GlobalPool&#40;mean&#41;</code>, which takes in the node embeddings of all nodes in the mini-batch and the assignment vector <code>graph_indicator</code> to compute a graph embedding of size <code>&#91;hidden_channels, batchsize&#93;</code>.</p>
<p>The final architecture for applying GNNs to the task of graph classification then looks as follows and allows for complete end-to-end training:</p>
</div>

<pre class='language-julia'><code class='language-julia'>function create_model(nin, nh, nout)
    GNNChain(GCNConv(nin =&gt; nh, relu),
             GCNConv(nh =&gt; nh, relu),
             GCNConv(nh =&gt; nh),
             GlobalPool(mean),
             Dropout(0.5),
             Dense(nh, nout))
end</code></pre>
<pre id='var-create_model' class='code-output documenter-example-output'>create_model (generic function with 1 method)</pre>


<div class="markdown"><p>Here, we again make use of the <code>GCNConv</code> with <span class="tex">$\mathrm&#123;ReLU&#125;&#40;x&#41; &#61; \max&#40;x, 0&#41;$</span> activation for obtaining localized node embeddings, before we apply our final classifier on top of a graph readout layer.</p>
<p>Let&#39;s train our network for a few epochs to see how well it performs on the training as well as test set:</p>
</div>

<pre class='language-julia'><code class='language-julia'>function eval_loss_accuracy(model, data_loader, device)
    loss = 0.
    acc = 0.
    ntot = 0
    for (g, y) in data_loader
        g, y = g |&gt; device, y |&gt; device
        n = length(y)
        ŷ = model(g, g.ndata.x)
        loss += logitcrossentropy(ŷ, y) * n 
        acc += mean((ŷ .&gt; 0) .== y) * n
        ntot += n
    end 
    return (loss = round(loss/ntot, digits=4), acc = round(acc*100/ntot, digits=2))
end</code></pre>
<pre id='var-eval_loss_accuracy' class='code-output documenter-example-output'>eval_loss_accuracy (generic function with 1 method)</pre>

<pre class='language-julia'><code class='language-julia'>function train!(model; epochs=200, η=1e-2, infotime=10)
    # device = Flux.gpu # uncomment this for GPU training
    device = Flux.cpu
    model = model |&gt; device
    ps = Flux.params(model)
    opt = ADAM(1e-3)
    

    function report(epoch)
        train = eval_loss_accuracy(model, train_loader, device)
        test = eval_loss_accuracy(model, test_loader, device)
        @info (; epoch, train, test)
    end
    
    report(0)
    for epoch in 1:epochs
        for (g, y) in train_loader
            g, y = g |&gt; device, y |&gt; device
            gs = Flux.gradient(ps) do
                ŷ = model(g, g.ndata.x)
                logitcrossentropy(ŷ, y)
            end
            Flux.Optimise.update!(opt, ps, gs)
        end
        epoch % infotime == 0 && report(epoch)
    end
end</code></pre>
<pre id='var-train!' class='code-output documenter-example-output'>train! (generic function with 1 method)</pre>

<pre class='language-julia'><code class='language-julia'>begin
    nin = 7  
    nh = 64
    nout = 2
    model = create_model(nin, nh, nout)
    train!(model)
end</code></pre>



<div class="markdown"><p>As one can see, our model reaches around <strong>74&#37; test accuracy</strong>. Reasons for the fluctations in accuracy can be explained by the rather small dataset &#40;only 38 test graphs&#41;, and usually disappear once one applies GNNs to larger datasets.</p>
<h2>&#40;Optional&#41; Exercise</h2>
<p>Can we do better than this? As multiple papers pointed out &#40;<a href="https://arxiv.org/abs/1810.00826">Xu et al. &#40;2018&#41;</a>, <a href="https://arxiv.org/abs/1810.02244">Morris et al. &#40;2018&#41;</a>&#41;, applying <strong>neighborhood normalization decreases the expressivity of GNNs in distinguishing certain graph structures</strong>. An alternative formulation &#40;<a href="https://arxiv.org/abs/1810.02244">Morris et al. &#40;2018&#41;</a>&#41; omits neighborhood normalization completely and adds a simple skip-connection to the GNN layer in order to preserve central node information:</p>
<p class="tex">$$\mathbf&#123;x&#125;_i^&#123;&#40;\ell&#43;1&#41;&#125; &#61; \mathbf&#123;W&#125;^&#123;&#40;\ell &#43; 1&#41;&#125;_1 \mathbf&#123;x&#125;_i^&#123;&#40;\ell&#41;&#125; &#43; \mathbf&#123;W&#125;^&#123;&#40;\ell &#43; 1&#41;&#125;_2 \sum_&#123;j \in \mathcal&#123;N&#125;&#40;i&#41;&#125; \mathbf&#123;x&#125;_j^&#123;&#40;\ell&#41;&#125;$$</p>
<p>This layer is implemented under the name <code>GraphConv</code> in GNN.jl.</p>
<p>As an exercise, you are invited to complete the following code to the extent that it makes use of <code>GraphConv</code> rather than <code>GCNConv</code>. This should bring you close to <strong>82&#37; test accuracy</strong>.</p>
</div>


<div class="markdown"><h2>Conclusion</h2>
<p>In this chapter, you have learned how to apply GNNs to the task of graph classification. You have learned how graphs can be batched together for better GPU utilization, and how to apply readout layers for obtaining graph embeddings rather than node embeddings.</p>
</div>

<!-- PlutoStaticHTML.End -->
```


