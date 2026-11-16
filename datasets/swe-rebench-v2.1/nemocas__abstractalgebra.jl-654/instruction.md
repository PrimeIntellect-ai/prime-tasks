GF arithmetic broken for unsigned integers
I can say https://github.com/Nemocas/AbstractAlgebra.jl/blob/b2e4a749d666c7f76ee20c83a47217d55c6ca21f/src/julia/GF.jl#L177 is definitely broken for GFElem{UInt} since there are no negatives there. I would recommend:
For `+ on GFElem{UInt} or on GFElem{T} in general`, do `[HIDDEN]`. This should work because there is nothing to go wrong here.

Since julia's native Ints have defined 2s complement behaviour, for `+ on GFElem{Int}`, we can do `[HIDDEN]`. This optimization is kinda pointless because the parent check is probably going to preclude vectorization anyways.

_Originally posted by @tthsqe12 in https://github.com/Nemocas/AbstractAlgebra.jl/pull/652#issuecomment-702027390_

### Additional contract requirements

- Addition of `GFElem` values backed by integer types, including unsigned types, must return the field sum modulo the characteristic.
