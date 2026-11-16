`helm template --output-dir x --name release` renders to colliding path
Output of `helm version`: `Client: &version.Version{SemVer:"v2.13.1", GitCommit:"618447cbf203d147601b4b9bd7f8c37a5d39fbb4", GitTreeState:"clean"}`

Output of `kubectl version`: N/A

For example, say I want to render two releases of nginx, mine1 and mine2:
```
% helm template -n mine1 --output-dir out docs/examples/nginx
wrote out/nginx/templates/pre-install-secret.yaml
wrote out/nginx/templates/configmap.yaml
wrote out/nginx/templates/service.yaml
wrote out/nginx/templates/service-test.yaml
wrote out/nginx/templates/deployment.yaml
wrote out/nginx/templates/post-install-job.yaml
% helm template -n mine2 --output-dir out docs/examples/nginx
wrote out/nginx/templates/pre-install-secret.yaml
wrote out/nginx/templates/configmap.yaml
wrote out/nginx/templates/service.yaml
wrote out/nginx/templates/service-test.yaml
wrote out/nginx/templates/deployment.yaml
wrote out/nginx/templates/post-install-job.yaml
```
The second invocation clobbers the first. I would have expected `out/nginx/templates` to include the release name to avoid such a collision.

### Additional contract requirements

- The `pkg/action.Install` type must expose an exported boolean field named `UseReleaseName`.
- When `UseReleaseName` is true and `OutputDir` is set, rendered files must be written beneath `<OutputDir>/<ReleaseName>/`, preserving their chart-relative paths (for example, `<OutputDir>/<ReleaseName>/hello/templates/goodbye`).
- The `helm template` command must expose a boolean flag named `--release-name` that, when combined with `--output-dir`, writes each rendered file beneath `<output-dir>/<release-name>/` while preserving chart-relative paths, so that rendering different releases into the same output directory does not overwrite earlier output.
