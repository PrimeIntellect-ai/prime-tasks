`WCS.numerical_inverse` API has been broken
The `WCS.numerical_inverse`'s API was changed in version 0.24 slightly. The spring cleaning changes removed some pre-processing calls that fixed and stripped units prior to the inverse being called. Those were moved into the `WCS._call_backward` and `WCS.invert` methods.

That pre-processing should be restored so that `WCS.numerical_inverse`'s API works similarly to the `WCS.invert`.
