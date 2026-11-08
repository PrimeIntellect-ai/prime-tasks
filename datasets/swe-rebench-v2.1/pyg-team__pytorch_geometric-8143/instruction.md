`test/transforms/test_add_positional_encoding.py::test_eigenvector_permutation_invariance` fails with AMD CPU
### 🐛 Describe the bug

The unit test added in #8087 fails with the error bellow on AMD CPU based systems.


```
NVIDIA_TF32_OVERRIDE=0 pytest -s --cov --cov-report=xml test/transforms/test_add_positional_encoding.py::test_eigenvector_permutation_invariance
```

Traceback:
```
======================================================================== FAILURES ========================================================================$
_________________________________________________________ test_eigenvector_permutation_invariance ________________________________________________________$

    def test_eigenvector_permutation_invariance():
        edge_index = torch.tensor([[0, 1, 0, 4, 1, 4, 2, 3, 3, 5],
                                   [1, 0, 4, 0, 4, 1, 3, 2, 5, 3]])
        data = Data(edge_index=edge_index, num_nodes=6)

        perm = torch.tensor([5, 4, 3, 2, 1, 0])
        transform = AddLaplacianEigenvectorPE(
            k=1,
            is_undirected=True,
            attr_name='x',
            v0=torch.arange(data.num_nodes),
        )
        out1 = transform(data)

        transform = AddLaplacianEigenvectorPE(
            k=1,
            is_undirected=True,
            attr_name='x',
            v0=perm,
        )
        out2 = transform(data.subgraph(perm))

        print(out1.x[perm].abs())
        print(out2.x.abs())

>       assert torch.allclose(out1.x[perm].abs(), out2.x.abs(), atol=1e-1)
E       assert False
E        +  where False = <built-in method allclose of type object at 0x7f2f94b318a0>(tensor([[0.1360],\n        [0.5556],\n        [0.1924],\n        [0.1
360],\n        [0.5556],\n        [0.5556]]), tensor([[0.2091],\n        [0.5245],\n        [0.2957],\n        [0.2091],\n        [0.5245],\n        [0.524
5]]), atol=0.1)
E        +    where <built-in method allclose of type object at 0x7f2f94b318a0> = torch.allclose
E        +    and   tensor([[0.1360],\n        [0.5556],\n        [0.1924],\n        [0.1360],\n        [0.5556],\n        [0.5556]]) = <built-in method ab
s of Tensor object at 0x7f2bc6e1e160>()
E        +      where <built-in method abs of Tensor object at 0x7f2bc6e1e160> = tensor([[ 0.1360],\n        [-0.5556],\n        [ 0.1924],\n        [ 0.13
60],\n        [-0.5556],\n        [-0.5556]]).abs
E        +    and   tensor([[0.2091],\n        [0.5245],\n        [0.2957],\n        [0.2091],\n        [0.5245],\n        [0.5245]]) = <built-in method ab
s of Tensor object at 0x7f2bc89d3470>()
E        +      where <built-in method abs of Tensor object at 0x7f2bc89d3470> = tensor([[ 0.2091],\n        [-0.5245],\n        [ 0.2957],\n        [ 0.20
91],\n        [-0.5245],\n        [-0.5245]]).abs
E        +        where tensor([[ 0.2091],\n        [-0.5245],\n        [ 0.2957],\n        [ 0.2091],\n        [-0.5245],\n        [-0.5245]]) = Data(edge
_index=[2, 10], num_nodes=6, x=[6, 1]).x
```

### Environment

* PyG version: 2.4.0 (built from source)
* PyTorch version: 2.1.0
* OS:  Ubuntu 22.04.3 LTS
* Python version: 3.10.12
* CUDA/cuDNN version: 12.2
* How you installed PyTorch and PyG (`conda`, `pip`, source): source

### Additional contract requirements

For equivalent graph labelings, Laplacian positional encodings must remain valid for the same eigenvalue space. When an eigenvalue is repeated, correctness must not depend on selecting a particular orthonormal basis within that eigenspace.
