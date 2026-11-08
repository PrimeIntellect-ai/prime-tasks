Missing typ field in the header
There must be a `typ: "JWT"` field in the header. At least MapKit is giving a warning about it missing.
And there is no way to modify header, since it is created in `JWTSerializer` which is internal.

### Additional contract requirements

When signing a JWT, callers can optionally supply a content-type value for the `cty` header field by passing it to the signer's `sign` method as an argument labelled `cty` (for example `sign(payload, cty: "application/example")`). If supplied, that value is included in the JWT header; if omitted, no `cty` value is required. Every signed JWT includes `typ` with the value `JWT`.
