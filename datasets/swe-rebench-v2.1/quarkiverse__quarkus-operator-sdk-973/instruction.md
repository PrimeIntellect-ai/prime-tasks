CRD Generator is not generating multiple custom resource versions in case one version is tied to a reconciler
Hi,

Fabric8 CRD generator supports multiple versions of the same kind:
https://github.com/fabric8io/kubernetes-client/blob/main/doc/CRD-generator.md#multiple-custom-resource-versions

This does not work for us. We have two versions (v1 and v2) of the same custom resource. We set [quarkus.operator-sdk.crd.generate-all](https://docs.quarkiverse.io/quarkus-operator-sdk/dev/includes/quarkus-operator-sdk.html#quarkus-operator-sdk_quarkus-operator-sdk-crd-generate-all) to true. When no version is tied to a reconciler, both versions will be generated, but when we use one version (v2) by the reconciler, only this version is generated and the other (v1) is ignored.

Is this intended behavior or a bug?

note: Quarkus platform version is 3.10.2
