`FixedEmbeddingComposite` is inefficient for subgraph embeddings
When "embedding" is a one-to-one map between source and target nodes (i.e. source graph is a subgraph of the target graph), use of `FixedEmbeddingComposite` is inefficient (slow) due to:
- chain strength calculation during embedding (e.g. `uniform_torque_compensation()` calculated on source BQM)
- slow source BQM iteration and embedded BQM generation, while simple variable relabeling suffices
- during unembedding, chain breaks are resolved

Possible improvement would be to short-circuit embedding/unembedding for subgraphs.

Initially raised in https://github.com/dwavesystems/dwave-pytorch-plugin/issues/11.

See also #580.

### Additional contract requirements

For a one-to-one embedding supplied to `FixedEmbeddingComposite`, sampling must use variable relabeling rather than generating a full embedded BQM, must not calculate chain strength, and must not resolve chain breaks during unembedding. The returned samples must use the source BQM's variable labels.
