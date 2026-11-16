how can I clone repos to `/home/coder`?
By default, envbuilder will clone workspaces to `/workspaces/<repo-name>`. However, when I configure `ENVBUILDER_WORKSPACE_FOLDER` to `/home/coder`, it clones it directly in that folder, not `/home/coder/<repo-name>`.

What can I do here?

### Additional contract requirements

A user can choose the parent directory for a workspace separately from the final workspace folder, using `--workspace-base-dir`. When no explicit final folder is selected, the repository is placed in a subdirectory named after the repository; the default parent remains `/workspaces`. If the repository URL is absent or unusable, use an `empty` subdirectory under the selected parent. When an explicit final workspace folder is selected, use that path as the final workspace folder without appending the repository name.
