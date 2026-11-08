The providerID field is not set on the Machine object
### What happened?
These logs are from the cloud controller manager when running DigitalOcean conformance tests.
Some of the pods are stuck in a Pending state.

```
E0216 14:02:16.023047    1 node_controller.go:244] "Unhandled Error" err="error syncing 'e2e-vvx9c-6867588b9d-9kgbt': failed to get instance metadata for node e2e-vvx9c-6867588b9d-9kgbt: determining droplet ID from providerID: provider ID cannot be empty, requeuing" logger="UnhandledError"
I0216 14:02:18.070563    1 node_controller.go:429] Initializing node e2e-vvx9c-6867588b9d-4ttwd with cloud provider
I0216 14:02:18.070624    1 node_controller.go:233] error syncing 'e2e-vvx9c-6867588b9d-4ttwd': failed to get instance metadata for node e2e-vvx9c-6867588b9d-4ttwd: determining droplet ID from providerID: provider ID cannot be empty, requeuing
```

<!-- Try to provide as much information as possible.
If you're reporting a security issue, please check the guidelines for reporting security issues:
https://github.com/kubermatic/kubermatic/blob/main/CONTRIBUTING.md#reporting-a-security-vulnerability -->



### Expected behavior
The conformance test for DigitalOcean should pass without any problems.
<!-- What did you expected to happen? -->


### How to reproduce the issue?
Just run the conformance tests for DigitalOcean.
<!-- Please provide as much information as possible, so we can reproduce the issue on our own. -->



### How is your environment configured?

- KKP version:
- Shared or separate master/seed clusters?:

### Provide your KKP manifest here (if applicable)

<!-- Providing an applicable manifest (KubermaticConfiguration, Seed, Cluster or other resources) will help us to reproduce the issue.
Please make sure to redact all secrets (e.g. passwords, URLs...)! -->

<details>

```yaml
# paste manifest here
```

</details>

### What cloud provider are you running on?
DigitalOcean
<!-- AWS, Azure, DigitalOcean, GCP, Hetzner Cloud, Nutanix, OpenStack, Equinix Metal (Packet), VMware vSphere, Other (e.g. baremetal or non-natively supported provider) -->



### What operating system are you running in your user cluster?

<!-- Ubuntu 20.04, Rocky Linux 8, Flatcar Linux, ... (optional, bug might not be related to user cluster) -->



### Additional information

<!-- Additional information about the bug you're reporting (optional). -->

### Additional contract requirements

DigitalOcean deployments must use a cloud-controller-manager version compatible with the machine controller so nodes can be initialized with usable instance metadata. For the affected supported Kubernetes versions, use DigitalOcean cloud-controller-manager v0.1.56; v0.1.57 has the reported regression.
