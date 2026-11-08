Registry tool: align check and style structures
I noticed that we have a [Severity](https://github.com/apigee/registry/blob/566d11f06d20d41b50291eb5c848a720d72761cf/google/cloud/apigeeregistry/v1/check/check_report.proto#L68) defined for checks and a [Severity](https://github.com/apigee/registry/blob/566d11f06d20d41b50291eb5c848a720d72761cf/google/cloud/apigeeregistry/v1/style/style_guide.proto#L113) defined for style guides. I'm not sure that we would want to merge them, but could they have the same values? One is ordered in increasing severity and the other decreasing.  I don't have a preference for increasing vs. decreasing order, but think that the check Severity, being newer, would be easier to change.

### Additional contract requirements

- - The generated Go enum-value map `rpc.Problem_Severity_value` must contain every name in `rpc.Rule_Severity_value`, and each name must map to the same numeric value in both maps.
