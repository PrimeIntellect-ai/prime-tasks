NetworkPolicy.spec.ingress.from is not correctly serialized
**Describe the bug**


A network policy resource is correctly deserialized when read from the cluster.
The ingress spec is correctly converted from `from` to `_from`.  See https://github.com/kubernetes-client/javascript/blob/main/src/gen/models/V1NetworkPolicyIngressRule.ts#L24

But the serialization (e.g. when using with `client.replace`) does not correctly set `from` field. see the snippet below.

**Client Version**
e.g. `1.1.2`

**To Reproduce**
 See example

**Expected behavior**

Resource is correctly serialized

**Example Code**

```
const netPol: V1 NetworkPolicy = {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'NetworkPolicy',
        metadata: {
            name: 'test',
            namespace: 'default',
        },
        spec: {
            podSelector: {
                matchLabels: {
                    app: 'workspace',
                },
            },
            policyTypes: ['Ingress', 'Egress'],
            ingress: [
                {
                    _from: [{
                        podSelector: {matchLabels: {app: 'foo'}},
                    }],
                    ports: [{port: 123}],
                },
            ],
            egress: [
                {
                    to: [{
                        matchLabels: {app: 'bar'},
                    }],
                },
            ],
        },
    };
    client.create(netPol); // does not include the spec.ingress.from fields
```

**Environment (please complete the following information):**

- OS: Linux
- Node.js version: 22
