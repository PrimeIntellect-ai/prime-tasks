Support Environments and Environment Secrets
I was about to start work on adding Repository environments to the terraform provider when I realised the endpoints hadn't made it into this module yet. If I get a chance i'll give it a go (if no-one beats me to it)!

https://docs.github.com/en/rest/reference/repos#environments
https://docs.github.com/en/rest/reference/actions#create-or-update-an-environment-secret

### Additional contract requirements

Add the following public API to package `github`.

Environment secrets on `ActionsService`:
- `GetEnvPublicKey(ctx context.Context, repoID int, env string) (*PublicKey, *Response, error)`
- `ListEnvSecrets(ctx context.Context, repoID int, env string, opts *ListOptions) (*Secrets, *Response, error)`
- `GetEnvSecret(ctx context.Context, repoID int, env string, secretName string) (*Secret, *Response, error)`
- `CreateOrUpdateEnvSecret(ctx context.Context, repoID int, env string, eSecret *EncryptedSecret) (*Response, error)`
- `DeleteEnvSecret(ctx context.Context, repoID int, env string, secretName string) (*Response, error)`

Environments on `RepositoriesService`:
- `ListEnvironments(ctx context.Context, owner string, repo string) (*EnvResponse, *Response, error)`
- `GetEnvironment(ctx context.Context, owner string, repo string, name string) (*Environment, *Response, error)`
- `CreateUpdateEnvironment(ctx context.Context, owner string, repo string, name string, environment *CreateUpdateEnvironment) (*Environment, *Response, error)`
- `DeleteEnvironment(ctx context.Context, owner string, repo string, name string) (*Response, error)`

Public model types: `Environment`, `EnvResponse`, `EnvReviewers`, `BranchPolicy`, `ProtectionRule`, `RequiredReviewer`, `CreateUpdateEnvironment`.

`CreateUpdateEnvironment.MarshalJSON() ([]byte, error)` emits a zero wait timer as `0` rather than `null`.

`RequiredReviewer` exposes the reviewer type discriminator (`"User"` or `"Team"`) decoded from the API response through `GetType() string`.

The following getters return the corresponding field value, or the zero value when the receiver or the field is nil:
- `BranchPolicy.GetCustomBranchPolicies() bool`, `BranchPolicy.GetProtectedBranches() bool`
- `CreateUpdateEnvironment.GetDeploymentBranchPolicy() *BranchPolicy`, `CreateUpdateEnvironment.GetWaitTimer() int`
- `Environment.GetCreatedAt() Timestamp`, `Environment.GetDeploymentBranchPolicy() *BranchPolicy`, `Environment.GetEnvironmentName() string`, `Environment.GetHTMLURL() string`, `Environment.GetID() int64`, `Environment.GetName() string`, `Environment.GetNodeID() string`, `Environment.GetOwner() string`, `Environment.GetRepo() string`, `Environment.GetUpdatedAt() Timestamp`, `Environment.GetURL() string`, `Environment.GetWaitTimer() int`
- `EnvResponse.GetTotalCount() int`
- `EnvReviewers.GetID() int64`, `EnvReviewers.GetType() string`
- `ProtectionRule.GetID() int64`, `ProtectionRule.GetNodeID() string`, `ProtectionRule.GetType() string`, `ProtectionRule.GetWaitTimer() int`
- `RequiredReviewer.GetType() string`
