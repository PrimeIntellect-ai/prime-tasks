`ArrayBase::as_slice_memory_order` returns `None` when slice has a single element
For some reason, `as_slice_memory_order` returns `None` when called on a 1-element slice. Minimal example:

```rust
use ndarray::{s, Array1};
let arr = Array1::from_vec(vec![1.0, 2.0, 3.0]);
println!("{:?}", arr.slice(s![0..1]).as_slice_memory_order());
// Prints None
```
