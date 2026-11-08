Unexport point methods
[This](https://github.com/NethermindEth/juno/blob/cbd368b222ac19a69e75e8ab82f01443ad21f590/pkg/crypto/pedersen/points.go#L2062) and any other method that is defined on a point do not have to be exported.

### Additional contract requirements

- In package `pkg/crypto/pedersen`, the unexported type `point` must not expose any exported methods.
- The point addition method is named `add` and has the signature `func (p *point) add(other *point)`. It mutates the receiver in place to become the elliptic-curve sum of the two points modulo the curve prime. If either operand is the point at infinity, the result is the other point (or remains the point at infinity if both are).
