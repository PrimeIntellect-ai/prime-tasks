[PSyAD] Add support for logical scalar arguments in test harness generation.
`tl_poly1d_vert_adv_kernel_type` has a scalar argument of `logical` type. As it's a scalar it is read only but the test harness still needs to be extended to support this case.

### Additional contract requirements

The generated harness must initialize a logical scalar to a valid logical value before invoking the kernel. Logical scalars must be passed to the kernel invocation but must not be included as numeric operands in the generated adjoint inner-product sums.
