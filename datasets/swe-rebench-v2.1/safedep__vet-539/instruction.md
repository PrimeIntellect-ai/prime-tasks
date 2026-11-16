Add Sync Reporter Environment Resolver for GitHub
The sync reporter syncs `vet` data with SafeDep Cloud. This reporter need _optional_ input from the environment such as source (GitHub, Gitlab, Git etc), repository URL, trigger etc. The contract is defined as:

https://github.com/safedep/vet/blob/main/pkg/reporter/sync.go#L33

Currently we are using a default resolver which just returns empty values.

We need to add support for different CI resolvers such as GitHub, Gitlab etc. To start with, let us support only GitHub because thats where our primary user base exist.

Add support for GitHub Action environment resolver based on GitHub Actions default environment variables.

We also need to add a factory function such as `NewSyncReporterEnvironmentResolver` that leverages some heuristic to check if we are running in GitHub Actions, if so, return the GHA environment resolver.

We should fallback to the existing default resolver (No Op) if GHA environment is not detected.

### Additional contract requirements

When detecting GitHub Actions and populating sync metadata, use `GITHUB_ACTIONS` as the detection variable and read the repository URL from `GITHUB_SERVER_URL` and `GITHUB_REPOSITORY`, the trigger from `GITHUB_EVENT_NAME`, the git ref from `GITHUB_REF`, and the commit SHA from `GITHUB_SHA`. The application's normal sync reporting path must use the environment-resolver factory so the detected metadata is included in sync session creation.
