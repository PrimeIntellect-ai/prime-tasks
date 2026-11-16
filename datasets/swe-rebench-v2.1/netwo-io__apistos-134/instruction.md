Usage of Actix-Specific Features Without Actix Feature Flag
I've noticed that Actix-specific components like `Either` are being used outside the scope of the `actix` feature flag, which could lead to issues in non-Actix environments where the feature is not enabled.

For instance, in this snippet from [this file](https://github.com/netwo-io/apistos/blob/c21d1658e21796f7134e05682d544a5730b0996c/apistos-core/src/api_component.rs#L4):

```rust
#[cfg(feature = "actix")]
use crate::{PathItemDefinition, ResponseWrapper};
use actix_web::Either;
```
The `Either` type is used without proper feature gating.

**Expected Behavior**:
Actix-specific imports and types should be guarded by the appropriate `#[cfg(feature = "actix")]` to ensure compatibility with non-Actix environments.

**Steps to Reproduce**:
Try to compile `apistos-core` without the `actix` feature enabled, and errors related to `actix_web::Either` will occur.

**Proposed Solution**:
[HIDDEN]

### Additional contract requirements

- `apistos-core` must compile successfully when the `actix` feature is disabled, for example with `cargo build -p apistos-core --no-default-features`.
