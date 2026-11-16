Handle ExternalName services
As of today, services of type `ExternalName` does not seem to be supported by ExternalDNS as they don't have an endpoint attached to them, which simply ends up with a print in the debug logs: https://github.com/kubernetes-incubator/external-dns/blob/6d2b83cbf2d91866b41510ec2ad4ba7e27449898/source/service.go#L148-L151

This seems particularly weird as it is written in the helpers that `--service-type-filter` can take `ExternalName` as a value.

### Additional contract requirements

When an `ExternalName` Service with a DNS hostname in `spec.externalName` is selected for processing, produce a DNS alias endpoint targeting that configured hostname instead of dropping the Service because it has no ordinary endpoint.
