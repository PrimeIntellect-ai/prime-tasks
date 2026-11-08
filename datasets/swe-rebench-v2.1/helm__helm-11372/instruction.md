Flag --repository-cache used for finding helm-manager-* ‘ad hoc’ repository indexes, but not for creating them
Output of `helm version`:
```text
version.BuildInfo{Version:"v3.9.4", GitCommit:"dbc6d8e20fe1d58d50e6ed30f09a04a77e4c68db", GitTreeState:"clean", GoVersion:"go1.19"}
```
But this bug applies to older versions of Helm 3 equally, also on Linux.

Output of `kubectl version`: `Client Version: v1.23.5`

Cloud Provider/Platform (AKS, GKE, Minikube etc.): Any and all (N/A)


When using the `--repository-cache` flag in conjunction with a `helm dependency update` command while the Helm chart affected has a dependency for which there is no repo ‘alias’ defined (i.e. its URL has not been added with a `helm repo add (…)` command; often called an ‘unmanaged’ repo), an ‘ad hoc’ repository index file, named `helm-manager-*-index.yaml` (along with a file with the same base name, but ends with `-charts.txt`), will be created in the default repository cache directory, but a later step tries to find it in the directory that was set via the flag.

Example of the error message (this was on _macOS_):
>Update Complete. ⎈Happy Helming!⎈
Error: no cached repository for helm-manager-0199bcabd1392eb1d12164d7fc1f56a975ac01570d110f202cb3a78614ce224b found. (try 'helm repo update'): open /Users/someone/tmp/x/helm-manager-0199bcabd1392eb1d12164d7fc1f56a975ac01570d110f202cb3a78614ce224b-index.yaml: no such file or directory

## How to reproduce

The default directories mentioned in the instructions are the ones for Linux.

### Setup and check the ‘standard’ usage

- Remove all files from the default repo index cache dir: `rm -f ~/.cache/helm/repository/*`
- Create a new Helm chart in a temporary directory: `helm create test`
- Change the current working directory to that chart: `cd test`
- Add a (can be fake) dependency to the `Chart.yaml` file, referring to a repository you don’t have registered with Helm yet, e.g.:
```yaml
dependencies:
- name: test
  repository: https://cetic.github.io/helm-charts
  version: "1.0.0"
```
- Run `helm dependency update` (that works, but if you have a fake dependency it’ll tell you that it can’t be found in the repo)
- List the default repo cache dir: `ls -lat ~/.cache/helm/repository`; you’ll find indexes for all ‘managed’ repos, e.g. for Bitnami, SonarQube, etc.; there’s an ‘ad hoc’ index for that ‘unmanaged’ repo we added as a dependency as well, named `helm-manager-<some-hash>-charts.txt` and `helm-manager-<some-hash>-index.yaml`
- To start with a clean slate, remove the indexes again: `rm -f ~/.cache/helm/repository/*`

### Reproduce the bug with the flag
- Not needed, but to make the scenario more realistic and to prove this doesn’t make a difference, explicitly update the repo indexes, but in the alternative cache dir: `helm --repository-cache /tmp/helm-cache repo update`
- Check that the default repo cache dir is still empty: `ls -lat ~/.cache/helm/repository`
- Check that the repo indexes have been created in the specified alternative dir: `ls -lat /tmp/helm-cache`; obviously, no index files were created for the ‘unmanaged’ repo
- Wait at least a minute (because of the minimal delta between file time stamps)
- Run `helm --repository-cache /tmp/helm-cache dependency update` (it will fail with a message complaining that it can’t find a `helm-manager-*-index.yaml` file in directory `/tmp/helm-cache`)
- List the contents of the default repo index cache dir: `ls -lat ~/.cache/helm/repository`; you’ll notice the file mentioned in the error message is present there (along with newly created indexes for the ‘managed’ repos)
- List the contents of the alternative repo cache dir that was specified: `ls -lat /tmp/helm-cache`; notice that the (specific) `helm-manager-*-index.yaml` is not present and that the indexes for the ‘managed’ repos were not updated (touched)
