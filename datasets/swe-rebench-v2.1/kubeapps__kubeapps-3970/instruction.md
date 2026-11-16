Installed app not found right after installing a Carvel package
Parent issue: https://github.com/kubeapps/kubeapps/issues/3849

When a package is installed, we got redirected to the InstalledPackage view, which is great. The problem is that Kapp hasn't created the `App` resource yet. Alternatives (I'd go with 2)

1. Auto-retry from the UI in N attempts
    -  follow-up idea: should we add exp. backoff retries to every get-alike request to avoid transient API connectivity issues?
2. Check the `App` resource exists in the backend before sending the OK response back.

### Additional contract requirements

- If the `App` resource is not created, the request must return gRPC status `codes.Internal`.
