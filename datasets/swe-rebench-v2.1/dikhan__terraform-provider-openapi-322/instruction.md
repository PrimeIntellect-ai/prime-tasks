Upgrade to go 1.16 so Terraform SDK 2.10.1 can be integrated in the plugin
## Is your feature request related to a problem?

Terraform SDK latest release requires Go 1.16 to build the plugins as mentioned [in their documentation](https://github.com/hashicorp/terraform-plugin-sdk/tree/v2.10.1#go-compatibility).

Example:
```
As an OpenAPI Terraform maintainer
I want to update the go version used to build the plugin to Go v1.6
So that I we can integrate the latest version of Terraform SDK v2.10.1
```
## Describe the solution you'd like


## Acceptance criteria
What's required to consider this feature request complete?

- Go mod file is updated to document Go 1.6
- gorelease yaml file also uses Go 1.6
- documentation is updated mentioning the minimum require go version to use and build the plugin

## Describe alternatives you've considered
A clear and concise description of any alternative solutions or features you've considered.

## Additional context
Go release installation also requires Go 1.6 so this will enable the integration of the Terraform SDK latest version as well as remove from the CICD pipeline the installation script and be able to install go releaser using [go install](https://goreleaser.com/install/#go-install) method instead.

## Checklist (for admin only)

**Don't forget to go through the checklist to make sure the issue is created properly**:

- [x] I have added a corresponding label (feature request) to the issue (right side menu)
- [x] I have added this issue to the 'API Terraform Provider' GitHub project (right side menu)

### Additional contract requirements

The Go version to upgrade to is **1.16** (the "Go 1.6" wording in the acceptance criteria and example above is a typo for Go 1.16).

The project must consistently require Go 1.16 or newer to build the provider: the module language version is 1.16, the Travis build uses Go 1.16.x, and the README identifies Go 1.16 as the minimum build version. Travis installs GoReleaser using `go install` and no longer uses the legacy curl-based GoReleaser installation script. GoReleaser builds run with the Go toolchain selected by Travis, and its configuration must not override that with a version older than 1.16.
