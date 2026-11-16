add_random_edge does not check existing edges
### 🐛 Describe the bug

Calling add_random_edge may introduce duplicate edges that already existing in the graph. This may have unintended downstream consequences.

Minimal code to reproduce.

```python
edge_index = torch.IntTensor(([0, 1, 2, 0, 1, 2, 0, 1, 2], [0, 0, 0, 1, 1, 1, 2, 2, 2]))
torch_geometric.utils.add_random_edge(edge_index, 0.4, num_nodes=3)
```

### Additional contract requirements

Every edge returned as newly added by `add_random_edge` must not already occur in the input graph.

When training is enabled and the requested number of additions is positive, if eligible non-existing edges are available, `add_random_edge` must add at least one edge.
