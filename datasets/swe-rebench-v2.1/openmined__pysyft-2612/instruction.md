Fix precision with large storage fails
**Describe the bug**
The following operation fails

`lpt = torch.Tensor([-2., 4]).fix_prec(storage="large")`

**To Reproduce**
Steps to reproduce the behavior:
Use the above expression in a test and see the result:
`TypeError`
**Expected behavior**
The expression should not crash
**Screenshots**

**Desktop (please complete the following information):**

**Additional context**

### Additional contract requirements

- `torch.Tensor.fix_prec` accepts a `storage` keyword argument. Passing `storage="large"`
  selects the `LargePrecisionTensor` interpreter for storage: the returned tensor-like
  object wraps a `LargePrecisionTensor` (i.e. a `LargePrecisionTensor` appears in its
  wrapper chain), instead of the default `FixedPrecisionTensor`.
- `torch.Tensor.float_precision()` (also available as `float_prec`) restores a
  fixed-precision tensor to a regular `torch.Tensor`, scaling the stored integer values
  back to floating-point numbers using the original precision and base.
