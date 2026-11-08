TorchScript instance from torch.jit.script() runs successfully but throws type mismatch when loading from file
### 🐛 Describe the bug

In my example below, I can compile a Torchscript model of GENConv and compute the result Y1, however when I load the model from the saved file and try to calculate Y2 it throws a Type mismatch error. This is related to the input validation of Union[Tensor, OptPairTensor] in the Message Passing class. Torchscript requires the type to be the same for the true/false branches.

I'm not sure how to resolve this and am happy to contribute if someone can point me in the right direction.

I'm using the latest nightly build of pyg.

```
import torch
from torch import nn, Tensor
from torch_geometric.typing import Adj, OptTensor, Union, OptPairTensor
from torch_geometric.nn.conv import GENConv, GraphConv

class MyConv(nn.Module):
    def __init__(self):
        super(MyConv, self).__init__()
        self.conv = GENConv(64,
                            64,
                            learn_p=True,
                            num_layers=1)

    def forward(self, x: Union[Tensor, OptPairTensor], edge_index: Adj,
                edge_attr: OptTensor = None):
        y = self.conv(x, edge_index, edge_attr)
        return y

if __name__ == "__main__":
    device = 'cpu'
    save_path = "example.pt"
    model = MyConv()
    scripted_model = torch.jit.script(model)
    scripted_model.save(save_path)

    n_nodes = 200
    n_edges = 100
    x = torch.rand((n_nodes, 64), dtype=torch.float32, device=device)
    edge_index = torch.randint(2, (2, n_edges), dtype=torch.int64, device=device)
    edge_attr = torch.rand((n_edges, 64), dtype=torch.float32, device=device)

    y1 = scripted_model(x=x,
                                     edge_index=edge_index,
                                     edge_attr=edge_attr)

    model_from_file = torch.jit.load(save_path)
    y2 = model_from_file(x=x,
                                       edge_index=edge_index,
                                       edge_attr=edge_attr)
```

**Error:**
```
/miniforge3/envs/pyg/bin/python ...../Example.py
Traceback (most recent call last):
  File "......../Example.py", line 38, in <module>
    model_from_file = torch.jit.load(save_path)
  File "......../lib/python3.10/site-packages/torch/jit/_serialization.py", line 162, in load
    cpp_module = torch._C.import_ir_module(cu, str(f), map_location, _extra_files, _restore_shapes)  # type: ignore[call-arg]
RuntimeError:

Type mismatch: edge_index0 is set to type __torch__.torch_geometric.typing.SparseTensor (of Python compilation unit at: 0x561bb9716290) in the true branch and type Tensor in the false branch:
  File "code/__torch__/torch_geometric/nn/conv/gen_conv.py", line 52
      x0 = x2
    _7 = isinstance(edge_index, __torch__.torch_geometric.typing.SparseTensor)
    if _7:
    ~~~~~~
      edge_index1 = unchecked_cast(__torch__.torch_geometric.typing.SparseTensor, edge_index)
      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      edge_attr1 = ((edge_index1).__storage_getter()).value()
      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      edge_attr0, edge_index0 = edge_attr1, edge_index1
      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    else:
    ~~~~~
      edge_index2 = unchecked_cast(Tensor, edge_index)
      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      if _4(edge_index2, ):
      ~~~~~~~~~~~~~~~~~~~~~
        _8, value, = _5(edge_index2, )
        ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        if torch.gt(torch.dim(value), 1):
        ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
          _9 = True
          ~~~~~~~~~
        else:
        ~~~~~
          _10 = torch.__not__(bool(torch.all(value)))
          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
          _9 = _10
          ~~~~~~~~
        if _9:
        ~~~~~~
          edge_attr3 : Optional[Tensor] = value
          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        else:
        ~~~~~
          edge_attr3 = edge_attr
          ~~~~~~~~~~~~~~~~~~~~~~
        edge_attr2 : Optional[Tensor] = edge_attr3
        ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      else:
      ~~~~~
        edge_attr2 = edge_attr
        ~~~~~~~~~~~~~~~~~~~~~~
      edge_attr0, edge_index0 = edge_attr2, edge_index2
      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ <--- HERE
    if torch.__isnot__(edge_attr0, None):
      edge_attr5 = unchecked_cast(Tensor, edge_attr0)
and was used here:
  File "code/__torch__/torch_geometric/nn/conv/gen_conv.py", line 88
    else:
      edge_attr6 = edge_attr4
    out = (self).propagate(edge_index0, x0, edge_attr6, size, )
                           ~~~~~~~~~~~ <--- HERE
    x_dst = (x0)[1]
    if torch.__isnot__(x_dst, None):


Process finished with exit code 1
```



### Versions

pyg-nightly         2.4.0.dev20240205

pytorch                   2.1.2           py3.10_cuda12.1_cudnn8.9.2_0    pytorch
pytorch-cluster           1.6.3           py310_torch_2.1.0_cu121    pyg
pytorch-cuda              12.1                 ha16c6d3_5    pytorch
pytorch-lightning         2.1.3              pyhd8ed1ab_0    conda-forge
pytorch-mutex             1.0                        cuda    pytorch
pytorch-scatter           2.1.2           py310_torch_2.1.0_cu121    pyg
onnx                      1.15.0          py310heee6c8b_1    conda-forge
onnxruntime               1.16.3          py310hd4b7fbc_4_cpu    conda-forge
cuda-opencl               12.3.101                      0    nvidia
cuda-runtime              12.1.0                        0    nvidia
