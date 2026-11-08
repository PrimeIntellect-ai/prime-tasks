[Feature]: Differentiate between calling Container __init__ by user vs during object construction
### What would you like to see added to HDMF?

In PyNWB/HDMF, we often want to check that input parameters to an object's __init__ method are compliant with the schema. Over time, w may add new checks in __init__ that raise errors when a noncompliant set of parameters is provided. However, if this noncompliant set of parameters were allowed to be written by a previous version of the API, then files exist in the wild with this noncompliant set of parameters. Reading these files involves constructing the object using the object's constructor, which now raises an error. Even though these files are technically noncompliant, they still need to be readable by the current API.


### Is your feature request related to a problem?

_No response_

### What solution would you like?

Provide two different paths or a branching path in __init__ where calling __init__ by a user would raise an error if non-compliant data are provided but calling __init__ by the object construction process would raise a warning if non-compliant data are provided.

### Do you have any interest in helping implement the feature?

Yes.

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/hdmf-dev/hdmf/blob/dev/.github/CODE_OF_CONDUCT.md)
- [X] Have you checked the [Contributing](https://github.com/hdmf-dev/hdmf/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this change was not already [requested](https://github.com/hdmf-dev/hdmf/issues)?

### Additional contract requirements

- `AbstractContainer.__new__` accepts the keyword arguments `container_source`, `parent`, `object_id`, and `in_construct_mode` (default `False`).
- Every `AbstractContainer` instance exposes an attribute `_in_construct_mode`. Its value reflects the `in_construct_mode` value supplied to `__new__` (default `False`).
- When `object_id` is `None` or not supplied, a new UUID4 string is generated and used as the object's `object_id`.
- A container reconstructed from a file must be distinguishable from one created directly by a user while its `__init__` runs. Once construction is complete, the container must be out of construct mode.
- If parameters are noncompliant, direct user creation raises an error; reconstruction from an existing file emits a warning and still completes, so the file remains readable.
