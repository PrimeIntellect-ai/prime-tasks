Store CRD supports to provide the workload identity clientID
### What would you like to be added?

For oras using workload identity as auth provider, the clientID is only available from service account. Would like to support Store CRD to provide the ClientID same as certificateStore instead of from service account.

Current:
https://github.com/deislabs/ratify/blob/main/charts/ratify/templates/store.yaml
Store can only define the workload identity name.

Purpose:
support like
···
apiVersion: config.ratify.deislabs.io/v1alpha1
kind: Store
metadata:
  name: store-oras
spec:
  name: oras
  parameters:
    authProvider:
      clientID: 190d0258-5c9d-4ef2-890f-e12c163a2b3e
      name: azureWorkloadIdentity
    cacheEnabled: true
    capacity: 100
    keyNumber: 10000
    ttl: 10
···

### Anything else you would like to add?

_No response_

### Are you willing to submit PRs to contribute to this feature?

- [X] Yes, I am willing to implement it.

### Additional contract requirements

A Store's `parameters.authProvider` configuration supports a `clientID` value for the `azureWorkloadIdentity` provider. When that value is present, it is used as the Azure workload-identity client ID instead of the value from the service account. The default Store custom resource rendered by the Helm chart under `charts/ratify/templates/store.yaml` carries the configured workload-identity client ID into `spec.parameters.authProvider.clientID`.

The configuration is consumed by the public function `CreateAuthProviderFromConfig(config map[string]interface{}) (authprovider.AuthProvider, error)` in package `authprovider` (import path `github.com/deislabs/ratify/pkg/common/oras/authprovider`). The configuration map uses the key `"name"` to select the provider (for example `"azureWorkloadIdentity"`) and the key `"clientID"` to supply the client ID.

When the mandatory workload-identity environment variables are missing, the returned error message is exactly:
`required environment variables not set, AZURE_FEDERATED_TOKEN_FILE: , AZURE_AUTHORITY_HOST: `

When neither the configuration nor the `AZURE_CLIENT_ID` environment variable supplies a client ID, the returned error message is exactly:
`no client ID provided and AZURE_CLIENT_ID environment variable is empty`


- When rendering the default Store custom resource, use `.Values.azureWorkloadIdentity.clientId` as the configured workload-identity client ID.
