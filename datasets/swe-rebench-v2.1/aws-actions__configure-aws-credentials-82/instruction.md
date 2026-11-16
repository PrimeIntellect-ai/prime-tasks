Action fails when GITHUB_REF does not exist
Certain workflows don't set a GITHUB_REF variable, because the triggering event doesn't have a branch or tag. See [GitHub's docs on GITHUB_REF](https://help.github.com/en/actions/configuring-and-managing-workflows/using-environment-variables#default-environment-variables).

However, this action [fails with an error](https://github.com/aws-actions/configure-aws-credentials/blob/472e549195ba1f153e9fb72e39dc2a094e5de13e/index.js#L33) when the GITHUB_REF environment variable doesn't exist, with the output `##[error]Missing required environment value. Are you running in GitHub Actions?`.
