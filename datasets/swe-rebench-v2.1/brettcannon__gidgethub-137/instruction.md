Add support for Actions environment files
https://github.blog/changelog/2020-10-01-github-actions-deprecating-set-env-and-add-path-commands/
https://docs.github.com/en/free-pro-team@latest/actions/reference/workflow-commands-for-github-actions#environment-files
https://github.com/actions/toolkit/blob/main/packages/core/src/file-command.ts

### Additional contract requirements

Expose `gidgethub.actions.setenv(name, value)` to create or update an environment variable for the current action and persist the assignment through the Actions environment file for subsequent steps. Values containing multiple lines must be preserved.

Expose `gidgethub.actions.addpath(path)` to prepend a path to the current action's `PATH` and persist it through the Actions path file for subsequent steps.
