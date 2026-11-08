Using `helm lint <path> --quiet` produces no output, even when there's an error.
### What happened?

When running `helm lint <path> --quiet`, for some reason, `helm doesn't show any errors. However, if `--quiet` is removed, then errors are shown.

### Steps to reproduce

1. run `helm lint nonexistent/ --quiet`
2. No error is displayed despite that `nonexistent/` doesn't exist. The command exit code is `0` and not `1` to indicate an error.
3. run `helm lint nonexistent/`
4. the output is
```
==> Linting nonexistent/
Error unable to check Chart.yaml file in chart: stat nonexistent/Chart.yaml: no such file or directory

Error: 1 chart(s) linted, 1 chart(s) failed
```

1. run `mkdir charts/`
2. run `helm lint charts/ --quiet`
3. no error is displayed despite the missing `Chart.yaml`. The command exit code is `0` and not `1` to indicate an error.
4. run `helm lint charts/`
```
==> Linting charts/
Error unable to check Chart.yaml file in chart: stat charts/Chart.yaml: no such file or directory

Error: 1 chart(s) linted, 1 chart(s) failed
```

### Expected Behavior

As stated in the command usage `--quiet print only warnings and errors` which is not honored in this case. On error, the command should return `1`.

### Actual Behavior

No outputs at all, including errors. Even with a clear error, the command exit code is `0`.

### Additional context

Output of `helm version`: `version.BuildInfo{Version:"v3.10.0", GitCommit:"ce66412a723e4d89555dc67217607c6579ffcb21", GitTreeState:"clean", GoVersion:"go1.18.6"}`

Output of `kubectl version`: `Client Version: version.Info{Major:"1", Minor:"25", GitVersion:"v1.25.2", GitCommit:"5835544ca568b757a8ecae5c153f317e5736700e", GitTreeState:"clean", BuildDate:"2022-09-21T14:33:49Z", GoVersion:"go1.19.1", Compiler:"gc", Platform:"linux/amd64"}`

Cloud Provider/Platform (AKS, GKE, Minikube etc.): `k3s` and bare-metal

### Contributing

Vote on this issue by adding a 👍 reaction.
To contribute a fix for this issue, leave a comment (and link to your pull request, if you've opened one already).
