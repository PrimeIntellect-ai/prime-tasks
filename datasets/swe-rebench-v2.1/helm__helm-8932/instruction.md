helm repo search finds versions with dashes in them
Output of `helm version`:
version.BuildInfo{Version:"v3.3.4", GitCommit:"a61ce5633af99708171414353ed49547cf05013d", GitTreeState:"clean", GoVersion:"go1.14.9"}

Output of `kubectl version`:
Client Version: version.Info{Major:"1", Minor:"19", GitVersion:"v1.19.2", GitCommit:"f5743093fd1c663cb0cbc89748f730662345d44d", GitTreeState:"clean", BuildDate:"2020-09-16T13:41:02Z", GoVersion:"go1.15", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"18", GitVersion:"v1.18.2", GitCommit:"52c56ce7a8272c798dbc29846288d7cd9fbae032", GitTreeState:"clean", BuildDate:"2020-06-03T10:06:47Z", GoVersion:"go1.13.9", Compiler:"gc", Platform:"linux/amd64"}

Doing a `helm repo search test` gives:
```sh
$ helm search repo test
NAME                    CHART VERSION   APP VERSION     DESCRIPTION
repoA/test              1.17.0-0565674  0565674         A Helm chart for test
```

I thought that only chart versions that had the form `x.x.x` would be shown and not `x.x.x-x`. The latter should only be found if using `--devel`. Did I misunderstand this, or is this a bug?

### Additional contract requirements

- When `helm search repo nginx-ingress --devel` searches a repository containing `testing/nginx-ingress` with chart version `a.b.c.sdfsdf`, include that chart in the results and display its version as `a.b.c.sdfsdf`.
