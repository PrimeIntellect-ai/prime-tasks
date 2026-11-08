helm .Capabilities.KubeVersion giving unexpected results
Not sure if anyone faced the same issue before, While getting the kube version in helm chart using `{{ .Capabilities.KubeVersion.Minor }}` , It's not resolving it correctly. Always output value as 16.

As per my kube server version, i am expecting it to resolve as 18.

Output of `helm version`:
version.BuildInfo{Version:"v3.2.1", GitCommit:"fe51cd1e31e6a202cba7dead9552a6d418ded79a", GitTreeState:"clean", GoVersion:"go1.13.10"}

Can someone point me in the right direction here on what's missing.
Please let me know if you need any more info.

Output of `kubectl version`:
Client Version: version.Info{Major:"1", Minor:"13", GitVersion:"v1.13.10", GitCommit:"37d169313237cb4ceb2cc4bef300f2ae3053c1a2", GitTreeState:"clean", BuildDate:"2019-08-19T10:52:43Z", GoVersion:"go1.11.13", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"18", GitVersion:"v1.18.1", GitCommit:"7879fc12a63337efff607952a323df90cdc7a335", GitTreeState:"clean", BuildDate:"2020-04-08T17:30:47Z", GoVersion:"go1.13.9", Compiler:"gc", Platform:"linux/amd64"}

Cloud Provider/Platform (AKS, GKE, Minikube etc.): AWS cloud
NAME="CentOS Linux"
VERSION="7 (Core)"
ID="centos"
ID_LIKE="rhel fedora"
VERSION_ID="7"
PRETTY_NAME="CentOS Linux 7 (Core)"
ANSI_COLOR="0;31"

### Additional contract requirements

- The default `.Capabilities.KubeVersion.Version` must be `v1.18.0`.
