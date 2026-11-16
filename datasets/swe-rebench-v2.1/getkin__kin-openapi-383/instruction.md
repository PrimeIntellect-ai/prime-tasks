Parameters can't be overridden
When I'm trying to validate an openapi v3 yaml file with "parameters:" section under the path (with a single parameter)
and "parameters:" section under the operation (method) that should override the "global" parameter I'm getting this error:
"operation %s %s must define exactly all path parameters".

The bug is in "func (paths Paths) Validate(c context.Context)" at paths.go
The error is because code counts how many path parameters there is in the path (i.e. "pathParamsCount"),
the global parameters at the path level (i.e. "globalCount")
and the local parameters at the operation level (i.e. "count"),
[HIDDEN]

in the attached example you can see that I have:
1 path parameter (customer_id) - "pathParamsCount" = 1
1 global parameter - "globalCount" = 1
1 local parameter (that should override the global definition) - "count" = 1

therefore, the right comparison should be:
[HIDDEN]

[Test_param_override.zip](https://github.com/getkin/kin-openapi/files/6862404/Test_param_override.zip)

### Additional contract requirements

- When validation finds the missing path parameter in this case, it must return the exact error `invalid paths: operation GET /pets/{petId} must define exactly all path parameters (missing: [petId])`.
- When a path-level path parameter and an operation-level path parameter have the same name, the operation-level parameter overrides the path-level parameter. Validation must accept the operation when that parameter supplies the path-template parameter.
