KronckerProductLazyVariable only works for square and symmetric matrices
Easy enough to reproduce:

```python
a = torch.randn(5, 3)
b = torch.randn(2, 2)
kplv = KroneckerProductLazyVariable(NonLazyVariable(a), NonLazyVariable(b))
res = kplv._matmul(torch.randn(3 * 2)) # fails
```

This is blocking MultitaskKernel from working properly, so I'm trying to solve this now

### Additional contract requirements

Kronecker-product multiplication must match multiplication by the equivalent dense Kronecker matrix for compatible right-hand sides, including unbatched matrices with multiple columns, when factors are rectangular or nonsymmetric. Gradients through the multiplication with respect to the factors and right-hand side must agree with the equivalent dense multiplication.
