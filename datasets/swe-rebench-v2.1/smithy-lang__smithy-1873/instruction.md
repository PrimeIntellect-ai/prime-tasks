Protocols that support the `http` trait do not enforce that it must be attached to all operation shapes
As far as I'm aware, all protocols that support the `http` binding trait need to have it attached to all their `operation` shapes, which are routable using the required `http.uri` member.

(Aside: the above is not explicitly stated in the protocols' documentation pages)

However, the following model is accepted by Smithy (it's accepted with `restJson` too):

```smithy
$version: "2.0"

namespace com.amazonaws.simple

use aws.protocols#restXml

@restXml
service SimpleService {
    version: "2022-01-01",
    operations: [
        SimpleOperation,
    ],
}

//@http(uri: "/simple-operation", method: "GET")
operation SimpleOperation {
    output: SimpleOperationOutput,
}

structure SimpleOperationOutput {
    @required
    requiredString: String,
}
```

### Additional contract requirements

- For each operation missing the `http` trait when its service uses a protocol that supports it, the diagnostic message must be exactly: `The `<protocol-id>` protocol requires all operations in the `<service-id>` service define the `http` trait, but this operation is missing the `http` trait.` Replace `<protocol-id>` and `<service-id>` with the protocol and service shape IDs.
