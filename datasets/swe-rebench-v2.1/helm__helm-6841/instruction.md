Helm 3: helm inspect values does not show comments
Output of `helm version`:
version.BuildInfo{Version:"v3.0.0-beta.2", GitCommit:"26c7338408f8db593f93cd7c963ad56f67f662d4", GitTreeState:"clean", GoVersion:"go1.12.9"}

Output of `kubectl version`: N/A
Cloud Provider/Platform (AKS, GKE, Minikube etc.): N/A

The new `helm show values` (was `helm inspect`) outputs the parsed values.yaml of the chart with comments stripped out. This is a problem for helm charts that rely heavily on comments to document the exposed options (instead of repeating that information in the README).

I think default behavior should be the same as `helm inspect` and dump the values.yaml file verbatim. There's definitely value in presenting the parsed/stripped values as it does now, but this should probably be exposed with a flag (e.g. `--stripped`, `--parsed`, or `--no-comments`).
