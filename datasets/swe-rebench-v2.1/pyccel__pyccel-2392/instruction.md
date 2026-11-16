[Feature Request] Implement `expm1` function
### Is there an existing issue for this?

- [x] I have searched the existing issues

### Feature Description

`expm1` is a function to accurately compute values for `exp(x) - 1` which is important for small values of `x` (round-off errors). According to ChatGPT, both Fortran and C support this function.

### Use Case

I could compute values of `exp(x) - 1` more accurately for small `x`

### Benefits

_No response_

### Add Screenshots

_No response_

### Priority

High

### Record

- [x] I have read the [Contributing Guidelines](https://github.com/pyccel/pyccel/blob/devel/docs/CONTRIBUTING.md).
- [x] I have starred the repository

### Additional contract requirements

- Add support for the public NumPy function `numpy.expm1` (importable as `from numpy import expm1`).
