New rule for package command and Lambda
### Is this feature request related to a new rule or cfn-lint capabilities?

_No response_

### Describe the feature you'd like to request

Error message when using the package command and Lambda: `Runtime and Handler are mandatory parameters for functions created with deployment packages. `

### Describe the solution you'd like

A new warning or information rule that determines if you are using the package command and alerts that these parameters are required.

### Additional context

_No response_

### Is this something that you'd be interested in working on?

- [X] 👋 I may be able to implement this feature request

### Would this feature include a breaking change?

- [ ] ⚠️ This feature might incur a breaking change

### Additional contract requirements

- Surface this finding as a warning or informational finding, not an error.
- Treat a Lambda function as in scope for this check when its `PackageType` is `Zip`, or its `Code` specifies `ZipFile` or `S3Key`. Image-package functions are not in scope.
- For each in-scope function, report missing `Handler`, `Runtime`, or both; do not report either property as missing when it is present.
