SetTransformerAggregation returns `nan` for an unconnected node.
### 🐛 Describe the bug

When you use message passing with a `SetTransformerAggregation`  and the input graph includes any number of nodes that are disconnected from the rest of the graph, the `SetTransformerAggregation` returns `nan` for those nodes. This is in contrast to the `SumAggregation` which returns plain `0`.

```python
from torch import Tensor
import torch
from torch_geometric.nn import MessagePassing, SetTransformerAggregation
from torch_geometric.data import Data, Batch
from torch_geometric.utils import sort_edge_index

class MPNN4Set(MessagePassing):
    def __init__(self, dim, n_heads):
        super(MPNN4Set, self).__init__()
        self.dim = dim
        self.aggregator = SetTransformerAggregation(dim, heads=n_heads)

    def forward(self, h, edge_index, batch):
        edge_index = sort_edge_index(edge_index, sort_by_row=False)
        h = self.propagate(edge_index, x=h, num_nodes=h.size(0), batch=batch)

        return h

    def message(self, x_i, x_j, edge_index, num_nodes, batch):
        return x_j

    def aggregate(self, inputs: Tensor, index: Tensor, ptr: Tensor | None = None, dim_size: int | None = None) -> Tensor:
        h = self.aggregator(inputs, index, ptr, dim_size)
        return h

    def update(self, aggr_out, batch):
        return aggr_out


m = MPNN4Set(10, 2)
graphs = [Data(x=torch.randn((3, 10)), edge_index=torch.tensor([[0, 1], [1, 0]], dtype=torch.long)), Data(x=torch.randn((3, 10)), edge_index=torch.tensor([[0, 1, 2], [2, 1, 0]], dtype=torch.long))]

batched_graphs = Batch.from_data_list(graphs)

res = m(batched_graphs.x, batched_graphs.edge_index, batched_graphs.batch)

assert res[2].isnan().any().item() is True

```

I managed to debug this a little bit and it seems like this stems from the fact that in PyTorch's `MultiHeadAttention` implementation you shouldn't mask a row completely:

```python
import torch
from torch.nn import functional as F
from torch import nn

m = nn.MultiheadAttention(10, 2)

t1 = torch.randn((3, 3, 10))
mask = torch.tensor([[True, True, True], [False, False, False], [False, False, False]])

m(t1, t1, t1, mask) # Includes nan
```

This happens because the `unbatch` function will mask the row corresponding to that node because it is not connected to any other node.

### Environment

* PyG version: 2.3.1
* PyTorch version: 2.1.0a0+b5021ba
* OS: Ubuntu 22.04
* Python version: 3.10.6
* CUDA/cuDNN version: 12.2
* How you installed PyTorch and PyG (`conda`, `pip`, source): pip
