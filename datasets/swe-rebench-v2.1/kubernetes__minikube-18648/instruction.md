Current MINIKUBE_HOME environment variable setting logic is confusing
### What Happened?

We set `export MINIKUBE_HOME=~/somewhere_else/minikube`,

But after setting it, the real minikube home lies in `~/somewhere_else/minikube/.minikube`.

This is inconsistent with the usual XXX_HOME setting logic and is very confusing.

---

By looking at the code, we found the following logic and know why this happened: https://github.com/kubernetes/minikube/blob/5c0c9e8e7c20b603665204d065e418027e3a930a/pkg/minikube/localpath/localpath.go#L42-L51

Can anyone give more context why it is set up this way?

If no special reason, we should respect the `MINIKUBE_HOME` env var. i.e., the real minikube home should lies in `~/somewhere_else/minikube` rather than `~/somewhere_else/minikube/.minikube`.

### Attach the log file

N/A

### Operating System

None

### Driver

None
```[tasklist]
### Tasks
```
