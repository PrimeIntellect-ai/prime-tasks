sync manager task properties with CRD fields
**Describe the bug**

`parallel` flag for 2.2 repair is missing, check if CRD is in sync.

### Additional contract requirements

- In the `RepairTaskSpec` type in package `pkg/api/v1alpha1`, the `Intensity` field is a `*string`, so it can represent both integer values and decimal fractions (for example `"1"` or `"0.5"`).
- A repair task intensity value must be a valid floating-point number. A repair task whose intensity cannot be parsed as a float is rejected as invalid.
- The CustomResourceDefinition schema for repair tasks declares the `intensity` property as a string and includes the `parallel` property.
