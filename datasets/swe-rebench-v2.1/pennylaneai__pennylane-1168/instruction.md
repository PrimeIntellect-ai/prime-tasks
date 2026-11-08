[HIDDEN]
This is a features request: Please expose the shot vector via some public and documented property of the device. Thank you!

This is inspired by me needing to predict the output shape of certain QNodes and in case of a non trivial shot vector and all observables being owned by an `expval` the shape is
```
(sum([shot_tuple.copies for shot_tuple in [HIDDEN]]), len(self.measurements))
```
(where self is a tape).

### Additional contract requirements

- The `Device` class exposes a public property named `shot_vector`.
- `Device.shot_vector` returns the sparse shot distribution as a sequence of entries, preserving consecutive groups of identical shot values and recording, for each group, the shot value (`shots`) and how many times it repeats (`copies`).
- Each entry is a tuple-like object exposing `shots` and `copies` attributes.
