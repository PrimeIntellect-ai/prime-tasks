when killing `helm dep up` the next `dep up` fails
when killing the process running `helm dep up` it sometimes leave a temporary folder named `tmpcharts` and this makes the next `helm dep up` fail with the following error.
```
Error: Unable to move current charts to tmp dir: rename /mychart/charts /mychart/tmpcharts: file exists
```
This is easily reproducable by creating a folder named `tmpcharts` inside an helm chart root folder and try to launch `helm dep up`

Of course a workaround is to remove the folder manually before running the `helm dep up` but that would be great that helm did that automatically somehow.

<!-- If you need help or think you have found a bug, please help us with your issue by entering the following information (otherwise you can delete this text): -->

Output of `helm version`:
```
$helm version
Client: &version.Version{SemVer:"v2.12.2", GitCommit:"7d2b0c73d734f6586ed222a567c5d103fed435be", GitTreeState:"clean"}
Server: &version.Version{SemVer:"v2.13.1", GitCommit:"618447cbf203d147601b4b9bd7f8c37a5d39fbb4", GitTreeState:"clean"}
```
Output of `kubectl version`:
```
kubectl version
Client Version: version.Info{Major:"1", Minor:"13", GitVersion:"v1.13.3", GitCommit:"721bfa751924da8d1680787490c54b9179b1fed0", GitTreeState:"clean", BuildDate:"2019-02-04T04:48:03Z", GoVersion:"go1.11.5", Compiler:"gc", Platform:"darwin/amd64"}
Server Version: version.Info{Major:"1", Minor:"13", GitVersion:"v1.13.0", GitCommit:"ddf47ac13c1a9483ea035a79cd7c10005ff21a6d", GitTreeState:"clean", BuildDate:"2018-12-03T20:56:12Z", GoVersion:"go1.11.2", Compiler:"gc", Platform:"linux/amd64"}
```
Cloud Provider/Platform (AKS, GKE, Minikube etc.): docker for mac


The code handling this is here : https://github.com/helm/helm/blob/53d432fa58748412ff3dc10bc27cbf996d96c3ed/pkg/downloader/manager.go#L190
