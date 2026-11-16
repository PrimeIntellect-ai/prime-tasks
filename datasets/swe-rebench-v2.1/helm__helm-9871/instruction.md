helm 3.6.1: `--pass-credentials` required with urls: ['charts/foobar-0.0.2.tgz']
I've read the [security advisory](https://github.com/helm/helm/security/advisories/GHSA-56hp-xqp3-w2jf).

This works:

```
$ helm repo add --pass-credentials --username 'robot$mph-pull' --password $PASSWORD harbor-dev https://harbor.company.dk/chartrepo/dev
"harbor-dev" has been added to your repositories
$ helm fetch --version 0.0.2 harbor-dev/foobar
(works)
```

But if I don't provide --pass-credentials:

```
$ helm fetch --version 0.0.2 harbor-dev/foobar
Error: failed to fetch https://harbor.lessor.dk/chartrepo/dev/charts/foobar-0.0.2.tgz : 401 Unauthorized
```

When I look at https://harbor.lessor.dk/chartrepo/dev/index.yaml I see this for `foobar`:

```
  foobar:
  - apiVersion: v2
    appVersion: 0.0.1
    created: "2021-06-25T13:37:08.725501745Z"
    description: Foobar
    digest: 61f7daa97ead907afc0f89f5bcdd0021ccc41f3ebf27a4b92e7aa84baa1edc6a
    name: foobar
    type: application
    urls:
    - charts/foobar-0.0.2.tgz
    version: 0.0.2
```

I see nothing here to indicate that
> charts are being served from a different domain than the repository

which is what should require `--pass-credentials`.

In #9857,  @bacongobbler writes:

> The security release discusses a breaking change to the way Helm passes username/password credentials to the server hosting the chart package, listed in the urls field of the repository's index.yaml file. We no longer pass those credentials to upstream servers unless the URL

> 1. Is relative (e.g. /foo-1.0.0.tgz)
> 2. Is served from localhost (e.g. http://localhost/foo-1.0.0.tgz)
> 3. Is served from the same host (e.g. you used helm repo add foo https://foo.com, and the index.yaml referenced https://foo.com/foo-1.0.0.tgz)

A URL like 'charts/foobar-0.0.2.tgz` clearly is relative but also does not match the above list of criteria for "local" URLs. Is that the problem?

Output of `helm version`:

version.BuildInfo{Version:"v3.6.1", GitCommit:"61d8e8c4a6f95540c15c6a65f36a6dd0a45e7a2f", GitTreeState:"clean", GoVersion:"go1.16.5"}


Output of `kubectl version`:

Client Version: version.Info{Major:"1", Minor:"21", GitVersion:"v1.21.2", GitCommit:"092fbfbf53427de67cac1e9fa54aaa09a28371d7", GitTreeState:"clean", BuildDate:"2021-06-16T12:59:11Z", GoVersion:"go1.16.5", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"17", GitVersion:"v1.17.13", GitCommit:"30d651da517185653e34e7ab99a792be6a3d9495", GitTreeState:"clean", BuildDate:"2020-10-15T00:59:17Z", GoVersion:"go1.13.15", Compiler:"gc", Platform:"linux/amd64"}

Cloud Provider/Platform (AKS, GKE, Minikube etc.):

On-premise v1.17 k8s served by nutanix.
