Support preview revoke installation token endpoint
GitHub Developer API announcement:
https://developer.github.com/changes/2020-01-10-revoke-installation-token/

This would be a great PR for any new contributor to this repo or a new Go developer.
All contributions are greatly appreciated!

Feel free to volunteer for any issue and the issue can be assigned to you so that others don't attempt to duplicate the work.

Please check out our [CONTRIBUTING.md](https://github.com/google/go-github/blob/master/CONTRIBUTING.md) guide to get started.

Thank you!

### Additional contract requirements

Add a public method `RevokeInstallationToken(ctx context.Context) (*Response, error)` on `AppsService` in the `github` package (module `github.com/google/go-github/v29/github`). It sends a `DELETE` request to the `installation/token` endpoint with the preview `Accept` header `application/vnd.github.gambit-preview+json`. On success (HTTP status 204) it returns a non-nil `*Response` containing the HTTP metadata and a nil error; otherwise it returns an error describing the failure.
