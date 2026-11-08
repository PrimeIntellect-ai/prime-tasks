[Roadmap] PyG for Recommendation 🚀
### 🚀 The feature, motivation and pitch

**This roadmap aims to bring better support for recommendation tasks to PyG.**

Currently, all/most of our link prediction models are trained and evaluated using binary classification metrics. However, this usually requires that we have a set of candidates in advance, from which we can then infer the existence of links. This is not necessarily practical, since in most cases, we want to find the top-k most likely links from the full set of `O(N^2)` pairs.

While training can still be done via negative sampling and binary classification, this roadmap resolves around bringing better support for link prediction evaluation into PyG, with the following end-to-end pipeline:
1. Embed all source and destination nodes
1. Use "Maximum Inner Product Search" (MIPS) to find the top-k most likely links (via [`MIPSKNNIndex`](https://pytorch-geometric.readthedocs.io/en/latest/generated/torch_geometric.nn.pool.MIPSKNNIndex.html#torch_geometric.nn.pool.MIPSKNNIndex))
1. Evaluate using common metrics for recommendation, e.g., `map@k`, `precision@k`, `recall@k`, `f1@k`, `ndcg@k`.

### Metrics

We need to support recommendation metrics, which can be updated and computed in a mini-batch fashion. A related issue can be found [here](https://github.com/pyg-team/pytorch_geometric/issues/8271). Its interface can/should follow the `torchmetrics.Metric` interface, *e.g.*:
```python
class LinkPredMetric(torchmetrics.Metric):
    def __init__(self, k: int):
        pass

    def update(self, top_k_pred_mat: Tensor, edge_label_index: Tensor):
        pass

    def compute(self):
        pass
```
where `top_k_pred_mat` holds the top-k indices for each left-hand-side (LHS) entity, and `edge_label_index` holds the ground-truth information as a `[2, num_targets]` matrix.

* [x] Implement `LinkPredMetric` interface
* [x] Implement `map@k`
* [x] Implement `precision@k`
* [x] Implement `recall@k`
* [x] Implement `f1@k`
* [x] Implement `ndcg@k` (#8326)

### Examples

With this, we can build one or more clear and descriptive examples of how to leverage PyG for recommendation.

* [x] Select and implement one or two datasets commonly used for recommendation
* [x] Add exclusion logic to `MIPSKNNIndex`
* [x] Build an example that implements this pipeline
* [x] Write a tutorial about recommendation in PyG
* [x] Advanced: Combine PyG's recommendation capabilities with its temporal GNN support (see #3230)

### Additional contract requirements

- Add a public class `LinkPredRecall` in the module `torch_geometric.nn.metrics`, constructed as `LinkPredRecall(k: int)`.
- `LinkPredRecall`, `LinkPredPrecision`, and `LinkPredNDCG` are link-prediction retrieval metrics. Their `update(top_k_pred_mat, edge_label_index)` method accumulates a mini-batch of top-k predictions and ground-truth edges, and their `compute()` method returns a single scalar tensor holding the mean metric value over all source nodes that have at least one ground-truth edge.
- The string representation of these metrics is `LinkPredRecall(k={k})`, `LinkPredPrecision(k={k})`, and `LinkPredNDCG(k={k})` respectively, where `{k}` is the configured `k`.
