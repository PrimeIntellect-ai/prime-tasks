Helm repo add fails with some repositories
<!-- If you need help or think you have found a bug, please help us with your issue by entering the following information (otherwise you can delete this text): -->

`helm repo add` fails with certain repositories when using Helm v3.3.2. The issue does not occur with v3.3.1 or earlier versions.

Example:

```
helm repo add jetstack https://charts.jetstack.io
Error: looks like "https://charts.jetstack.io" is not a valid chart repository or cannot be reached: error unmarshaling JSON: while decoding JSON: json: unknown field "serverInfo"
```
The issue does not occur with every repository. For example, `https://kubernetes-charts.storage.googleapis.com/` can still be added:

```
helm repo add stable https://kubernetes-charts.storage.googleapis.com/
"stable" has been added to your repositories
```

Output of `helm version`:
```
version.BuildInfo{Version:"v3.3.2", GitCommit:"e5077257b6ca106d1f65652b4ca994736d221ab1", GitTreeState:"clean", GoVersion:"go1.14.9"}
```

Output of `kubectl version`:
```
Client Version: version.Info{Major:"1", Minor:"18", GitVersion:"v1.18.6", GitCommit:"dff82dc0de47299ab66c83c626e08b245ab19037", GitTreeState:"clean", BuildDate:"2020-07-15T16:58:53Z", GoVersion:"go1.13.9", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"18", GitVersion:"v1.18.6", GitCommit:"dff82dc0de47299ab66c83c626e08b245ab19037", GitTreeState:"clean", BuildDate:"2020-07-20T00:20:54Z", GoVersion:"go1.13.9", Compiler:"gc", Platform:"linux/amd64"}
```

Cloud Provider/Platform (AKS, GKE, Minikube etc.):

The issue was observed on both KIND and OpenStack clusters.
