clone via branch does not create a project dir
from a prospective customer:

> when creating a devcontainer workspace via a direct repo link (e.g. https://github.com/org/repo-name), the envbuilder clones the repo into the `repo-name` directory, so you get `/workspaces/repo-name/`… , but when creating via a branch link (e.g. https://github.com/org/repo-name/#refs/heads/jon-coder), the envbuilder seems to clone the repo contents directly into `workspaces`, so you get `/workspaces/`…

this is blocking their devcontainer use-case with Coder, because their build/service scripts rely on the source path in order to work, so the project not being in `/workspaces/repo-name/` is breaking the services.

### Additional contract requirements

- When the repository source is `/` or `//`, the default workspace folder must be `/workspaces/empty`.
