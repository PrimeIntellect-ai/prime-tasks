networking.k8s.io/v1beta1 should be flagged deprecated also
Since 1.19 has moved ingress to v1 could we alert on both v1beta1 strings?

[HIDDEN]

https://v1-19.docs.kubernetes.io/docs/setup/release/notes/#deprecations-and-removals
_Ingress and IngressClass resources have graduated to networking.k8s.io/v1. Ingress and IngressClass types in the extensions/v1beta1 and networking.k8s.io/v1beta1 API versions are deprecated and will no longer be served in 1.22+_


Once again thanks for the fantastic tool!
