Helm validation does not check if a chart uses an undefined repository
Given the following definition:

```
apiVersion: 1.0
image:
  arch: x86_64
  imageType: raw
  baseImage: SLE-Micro.x86_64-5.5.0-Default-GM.raw
  outputImageName: raw-image.raw
kubernetes:
  version: v1.28.7+k3s1
  helm:
    charts:
    - name: edge-stuff
      version: 0.14.3
      repositoryName: suse-edge
    - name: not-edge-stuff
      version: 0.14.3
      repositoryName: not-suse-edge
    repositories:
      - name: not-suse-edge
        url: https://suse-edge.github.io/charts
```

I would have expected a validation-time failure because `edge-stuff` references the repo `suse-edge` that doesn't exist. Instead, it goes until build time when I see the following in eib-build.log:

```
2024-04-08T14:25:59.787Z	WARN	kubernetes/cluster.go:103	Kubernetes config file '/eib/kubernetes/config/server.yaml' was not provided
2024-04-08T14:25:59.787Z	INFO	combustion/network.go:53	Configuring network component...
2024-04-08T14:25:59.787Z	INFO	combustion/network.go:57	Skipping network component, configuration is not provided
2024-04-08T14:25:59.787Z	INFO	combustion/rpm.go:32	Skipping RPM component. Configuration is not provided
2024-04-08T14:25:59.787Z	INFO	combustion/elemental.go:33	Skipping elemental registration component, configuration is not provided
2024-04-08T14:25:59.787Z	FATAL	build/build.go:102	An error occurred building the image: configuring combustion: configuring component "embedded artifact registry": configuring embedded artifact registry: parsing helm charts: repository not found for chart edge-stuff
github.com/suse-edge/edge-image-builder/pkg/cli/build.Run
	/home/abuild/rpmbuild/BUILD/edge-image-builder-1.0.0.rc3/pkg/cli/build/build.go:102
github.com/urfave/cli/v2.(*Command).Run
	/home/abuild/rpmbuild/BUILD/edge-image-builder-1.0.0.rc3/vendor/github.com/urfave/cli/v2/command.go:279
github.com/urfave/cli/v2.(*Command).Run
	/home/abuild/rpmbuild/BUILD/edge-image-builder-1.0.0.rc3/vendor/github.com/urfave/cli/v2/command.go:272
github.com/urfave/cli/v2.(*App).RunContext
	/home/abuild/rpmbuild/BUILD/edge-image-builder-1.0.0.rc3/vendor/github.com/urfave/cli/v2/app.go:337
github.com/urfave/cli/v2.(*App).Run
	/home/abuild/rpmbuild/BUILD/edge-image-builder-1.0.0.rc3/vendor/github.com/urfave/cli/v2/app.go:311
main.main
	/home/abuild/rpmbuild/BUILD/edge-image-builder-1.0.0.rc3/cmd/eib/main.go:19
runtime.main
	/usr/lib64/go/1.22/src/runtime/proc.go:271
```

@dbw7 Is this intentional? It's possible there's some other way of getting repos that I'm not aware of that can only be done at runtime, but on the surface this feels like a missing check.

### Additional contract requirements

- When a Helm chart references a repository name that does not match the name of any defined repository, validation must report exactly: `Helm chart 'repositoryName' "<repositoryName>" for Helm chart "<chartName>" does not match the name of any defined repository.`, substituting the chart's `repositoryName` and `name` values. For example, repository name `this-is-not-suse-edge` for Helm chart `metallb` must report: `Helm chart 'repositoryName' "this-is-not-suse-edge" for Helm chart "metallb" does not match the name of any defined repository.`
