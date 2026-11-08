TektonInstallerSet created have each resource twice
When we read resources from ko data and create installer set, the installer set has 2 copies of each resource.

for eg,
In addons, for clustertasks, when we read clustertasks from kodata [here](https://github.com/tektoncd/operator/blob/3c77c775a7464cb8fd42e4addace86298d5d39df/pkg/reconciler/openshift/tektonaddon/tektonaddon.go#L329) -> it calls [`applyAddons`](https://github.com/tektoncd/operator/blob/3c77c775a7464cb8fd42e4addace86298d5d39df/pkg/reconciler/openshift/tektonaddon/tektonaddon.go#L481)
in apply addon we pass the path of the directory to ` common.AppendManifest(manifest, addonLocation)` and it
reads all the resources at the location and returns inside the manifest obj
but the manifest has 2 copies of each resource so manifest is getting bigger.

It is probably issue with [AppendManifest](https://github.com/tektoncd/operator/blob/3c77c775a7464cb8fd42e4addace86298d5d39df/pkg/reconciler/common/releases.go#L176)

To reproduce the issue
1. install operator using `make TARGET=openshfit` apply` on Openshift
2. let `all` profile install all components
3. for addons there would 4 installler set created
4. check any installer set if there are 2 instances of each resource eg. in clustertask `addon-clustertask- ` installerset there would be 2 buildah clustertask which are same.

### Additional contract requirements

- Add a public function `AppendManifest(manifest *mf.Manifest, yamlLocation string) error` in package `pkg/reconciler/common`, where `mf` is `github.com/manifestival/manifestival`. It appends every Kubernetes resource found under the directory `yamlLocation`, including resources in nested subdirectories, to the supplied manifest. Resources already present in the supplied manifest are retained, and each resource found under `yamlLocation` is appended exactly once. It returns nil on success.
