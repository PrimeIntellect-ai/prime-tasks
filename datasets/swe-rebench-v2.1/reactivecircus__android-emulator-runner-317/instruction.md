Allow non-integer api-level
I would like to use upsidedown cake for the unit test. But the `api-level` only allows integers. How about allowing a non-integer `api-level`?

Hilariously, I posted this request since tiramusu #225 but nearly a year past, this is still not supported.

### Additional contract requirements

- The `api-level` input must accept non-integer Android codenames in addition to integer API levels. In particular, `UpsideDownCake` (including suffixed variants such as `UpsideDownCake-ext5`) and `TiramisuPrivacySandbox` must be accepted by the API level validation.
- When such a non-integer `api-level` is supplied, the action must use that exact value (as a string) when installing the system image and creating the AVD, rather than a numeric conversion of it.
