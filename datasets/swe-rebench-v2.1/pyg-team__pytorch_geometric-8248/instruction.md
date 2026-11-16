`MetaPath2Vec` fails in a heterogeneous graph with zero-degree nodes
### 🐛 Describe the bug

Just found that `MetaPath2Vec` does not work well on a heterogeneous graph with zero-degree nodes.
Here is the example to reproduce the bug:

```python
import torch
from torch_geometric.data import HeteroData
from torch_geometric.nn.models import MetaPath2Vec

data = HeteroData()
data['a'].x = torch.ones(3, 2)
data['b'].x = torch.ones(4, 2)
data[('a', 'to', 'b')].edge_index = torch.tensor([[0, 2], [0, 2]])
data[('b', 'to', 'a')].edge_index = torch.tensor([[0, 2], [0, 2]])

metapath = [('a', 'to', 'b'), ('b', 'to', 'a')]

model = MetaPath2Vec(data.edge_index_dict, embedding_dim=16,
                     metapath=metapath, walk_length=10, context_size=7,
                     walks_per_node=5, num_negative_samples=5,
                     num_nodes_dict=data.num_nodes_dict,
                     sparse=True)

loader = model.loader(batch_size=16, shuffle=True)
next(iter(loader))
```
It throws
```
    248 def sample(rowptr: Tensor, col: Tensor, rowcount: Tensor, subset: Tensor,
    249            num_neighbors: int, dummy_idx: int) -> Tensor:
    251     rand = torch.rand((subset.size(0), num_neighbors), device=subset.device)
--> 252     rand *= rowcount[subset].to(rand.dtype).view(-1, 1)
    253     rand = rand.to(torch.long) + rowptr[subset].view(-1, 1)
    255     col = col[rand]

IndexError: index 7 is out of bounds for dimension 0 with size 4
```

[HIDDEN]
[HIDDEN]


### Environment

* PyG version: master
* PyTorch version: 2.0.0
* OS: macos
* Python version: 3.10
* CUDA/cuDNN version: N/A
* How you installed PyTorch and PyG (`conda`, `pip`, source): pip
* Any other relevant information (*e.g.*, version of `torch-scatter`): N/A

### Additional contract requirements

- The `MetaPath2Vec` loader must yield a batch for heterogeneous graphs containing zero-degree nodes, including when one metapath edge type has no edges while another has edges, without raising an out-of-range-index error.
