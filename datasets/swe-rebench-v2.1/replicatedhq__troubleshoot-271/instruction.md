ImagePullSecret analyzer panics if pass or fail is nil
The folllowing spec results in a panic when outcome is pass

```yaml
apiVersion: troubleshoot.sh/v1beta2
kind: Preflight
metadata:
  name: preflight-sample
spec:
  analyzers:
    - imagePullSecret:
        checkName: Pull from local registry
        registryName: quay.io
        outcomes:
          - fail:
              message: You won't be able to pull from local registry
```

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x10 pc=0x172fcc2]

goroutine 1 [running]:
goroutine 1 [running]:
github.com/replicatedhq/troubleshoot/pkg/analyze.analyzeImagePullSecret(0xc00008d980, 0xc000b61978, 0x0, 0x0, 0x0)
        /home/areed/src/github.com/replicatedhq/troubleshoot/pkg/analyze/image_pull_secret.go:52 +0x322
github.com/replicatedhq/troubleshoot/pkg/analyze.Analyze(0xc000744480, 0xc000b619b0, 0xc000b61978, 0x0, 0x0, 0x0)
        /home/areed/src/github.com/replicatedhq/troubleshoot/pkg/analyze/analyzer.go:102 +0x8c5
github.com/replicatedhq/troubleshoot/pkg/preflight.CollectResult.Analyze(0xc00077db00, 0xc000169890, 0x2, 0x2, 0x0, 0xc000166f20, 0xc00077db00, 0xc000169890, 0x2)
        /home/areed/src/github.com/replicatedhq/troubleshoot/pkg/preflight/analyze.go:33 +0x18f
github.com/replicatedhq/troubleshoot/cmd/preflight/cli.runPreflights(0xc00024c500, 0x7fffa4ec8737, 0x9, 0x0, 0x0)
        /home/areed/src/github.com/replicatedhq/troubleshoot/cmd/preflight/cli/run.go:129 +0x9fc
github.com/replicatedhq/troubleshoot/cmd/preflight/cli.RootCmd.func2(0xc0006c5180, 0xc0006f10b0, 0x1, 0x1, 0x0, 0x0)
        /home/areed/src/github.com/replicatedhq/troubleshoot/cmd/preflight/cli/root.go:29 +0x4d
github.com/spf13/cobra.(*Command).execute(0xc0006c5180, 0xc000128030, 0x1, 0x1, 0xc0006c5180, 0xc000128030)
        /home/areed/pkg/mod/github.com/spf13/cobra@v0.0.5/command.go:826 +0x47c
github.com/spf13/cobra.(*Command).ExecuteC(0xc0006c5180, 0x0, 0x0, 0x0)
        /home/areed/pkg/mod/github.com/spf13/cobra@v0.0.5/command.go:914 +0x30b
github.com/spf13/cobra.(*Command).Execute(...)
        /home/areed/pkg/mod/github.com/spf13/cobra@v0.0.5/command.go:864
github.com/replicatedhq/troubleshoot/cmd/preflight/cli.InitAndExecute()
        /home/areed/src/github.com/replicatedhq/troubleshoot/cmd/preflight/cli/root.go:52 +0x2a
main.main()
        /home/areed/src/github.com/replicatedhq/troubleshoot/cmd/preflight/main.go:9 +0x25
```

### Additional contract requirements

- Analyzing an `imagePullSecret` analyzer must complete without panicking when its outcomes include only a pass outcome, only a fail outcome, or neither, whether or not credentials for the registry are found.
- When credentials for the registry are found the analysis reports a pass; otherwise it reports a fail.
- When the matching pass or fail outcome is configured, its message is used for the corresponding result.
