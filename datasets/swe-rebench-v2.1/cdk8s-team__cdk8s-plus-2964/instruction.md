Add IngressClassName to Ingress
### Description of the feature or enhancement:
We would like to be able to configure the `IngressClassName` on `Ingress` objects.


### Use Case:
The IngressClassName is part of the officiall documentation and was added within Kubernetes version 1.18.

"used to reference the name of the Ingress controller that should implement the Ingress, the field is a reference to an IngressClass resource that contains additional Ingress configuration, including the name of the Ingress controller" (https://kubernetes.io/docs/concepts/services-networking/ingress)


### Proposed Solution:
Currently we have implemented it as an extension like follows:
```
import { JsonPatch } from "cdk8s";
import { Ingress, IngressProps } from "cdk8s-plus-25";
import { Construct } from "constructs";

export class IngressWithClassName extends Ingress {
    constructor(scope: Construct, id: string, props: IngressProps & { ingressClassName: string }) {
        super(scope, id, props);

[HIDDEN]
    }
}
```



---

This is a :rocket: Feature Request

### Additional contract requirements

- The built-in `Ingress` API accepts an optional `className` property (in its props). When provided, the generated Kubernetes Ingress manifest must set `spec.ingressClassName` to its value.
