v3.7.0-rc.2: `helm dependency update` no longer works with `file://` repositories
Output of `helm version`: `version.BuildInfo{Version:"v3.7.0-rc.2", GitCommit:"4a7c306aa9dcbdeecf79c7517851921a21b72e56", GitTreeState:"clean", GoVersion:"go1.16.7"}`

Output of `kubectl version`: `Client Version: version.Info{Major:"1", Minor:"22", GitVersion:"v1.22.1", GitCommit:"632ed300f2c34f6d6d15ca4cef3d3c7073412212", GitTreeState:"clean", BuildDate:"2021-08-19T15:38:26Z", GoVersion:"go1.16.6", Compiler:"gc", Platform:"darwin/amd64"}
Server Version: version.Info{Major:"1", Minor:"20", GitVersion:"v1.20.7", GitCommit:"132a687512d7fb058d0f5890f07d4121b3f0a2e2", GitTreeState:"clean", BuildDate:"2021-05-27T23:27:49Z", GoVersion:"go1.15.12", Compiler:"gc", Platform:"linux/amd64"}`

Cloud Provider/Platform (AKS, GKE, Minikube etc.): kind

## Description

Running `helm dependency update` no longer works with `file://` repositories mentioned in Chart.yaml. I no longer see any `*.tgz` files get created in the `charts/` directory. This is a breaking regression that causes `helm install` to throw this error

```
Error: found in Chart.yaml, but missing in charts/ directory: ...
```

## Reproducing the issue

- Setup a `Chart.yaml` with local dependencies
```yaml
apiVersion: v2
name: my-umbrella-chart
version: 0.1.0
appVersion: 0.1.0
dependencies:
- name: nginx
  version: 0.1.0
  repository: file:///Users/saada/my-charts/nginx
```

- Use helm v3.6.1 and run `helm dependency update` and `/charts` gets populated correctly with the `nginx-0.1.0.tgz` file.
- Delete the tgz file
- Use helm v3.7.0-rc.2 and run `helm dependency update` and `/charts` remains empty. Running the same command with `--debug` mode shows the following logs which indicate that it should have succeeded

```
Repository from local path: file:///Users/saada/my-charts/nginx
Saving 1 charts
Archiving nginx from repo file: file:///Users/saada/my-charts/nginx
Deleting outdated charts
```
