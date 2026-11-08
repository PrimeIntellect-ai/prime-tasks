🚀 Feature: Turn the Node.js version used in CI into an Addon for blockGitHubActionsCI
### Feature Request Checklist

- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

Most of my repos run on the _latest_ known+supported Node.js version in CI. This hasn't been an issue yet that I know of, and I like running many repos on this "latest and greatest" strategy as a form of testing to see whether & how it ever could be.

But, some repos are higher visibility + usage and would prefer to run on the _oldest_ supported Node.js version in CI. They'll want to be able to customize the version set in the preparation action. Example: https://github.com/JoshuaKGoldberg/eslint-plugin-package-json/pull/993#discussion_r2032053502

### Additional Info

🎁

### Additional contract requirements

- The block accepts an addon named `nodeVersion` (a string or number) that sets the Node.js version used in the preparation action's `actions/setup-node` step. When the addon is not provided, the version defaults to the pinned Node.js version, falling back to the minimum supported version.
- The block exposes an `intake` method that reads the preparation action at `.github/actions/prepare/action.yml`. It returns `{ nodeVersion: string }`, where `nodeVersion` is the value of the `with["node-version"]` field of the `actions/setup-node` step. It returns `undefined` when the file is missing, when it does not contain a `runs.steps` array, when no step uses `actions/setup-node`, or when that step has no `node-version` input.
