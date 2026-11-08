Support Globalnet with Headless services
**What would you like to be added**:
Add support for Globalnet + Headless services

**Why is this needed**:
Current Globalnet deployments don't support headless services due to technical limitations. But [Globalnet v2](https://github.com/submariner-io/submariner/issues/652) supports headless services. This require changes in Lighthouse too.

### Additional contract requirements

- When Globalnet is enabled for a headless service, the global IP allocated to an endpoint backed by pod `<pod-name>` is published in a `GlobalIngressIP` resource named `pod-<pod-name>` in the service's namespace. The synced EndpointSlice uses that allocated global IP as the endpoint address.
