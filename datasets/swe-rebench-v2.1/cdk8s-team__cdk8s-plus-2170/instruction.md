`exposeViaService` does not expose port names
<!--Please make sure to read the "Reporting Issues" section of the contribution guide before submitting an issue
https://github.com/cdk8s-team/cdk8s/blob/master/CONTRIBUTING.md#reporting-issues
-->

### Description of the bug:
Given a port definition in a `Deployment`:
```
ports: [
    { number: 3000, name: 'http' },
    { number: 8080, name: 'dashboard' }
]
```
`deployment.exposeViaService()` produces:
```
  ports:
    - port: 3000
      targetPort: 3000
    - port: 8080
      targetPort: 8080
```
which is incorrect according to [Kubernetes documentation](https://kubernetes.io/docs/concepts/services-networking/service/#multi-port-services):

> When using multiple ports for a Service, you must give all of your ports names so that these are unambiguous.

Since the names are already there in the definition, I would have expected them to be applied automatically. [HIDDEN]
    const ports: service.ServicePort[] = options.ports ?? myPorts.map(p => ({ port: p.number, targetPort: p.number, protocol: p.protocol, name: p.name }));
```
---

This is :bug: Bug Report

### Additional contract requirements

- When the Service ports for `exposeViaService()` are derived from the Deployment's container ports, each Service port must carry the name of the container port it targets, so that a Deployment with named ports exposes those names on its Service.
