semaphore limit leads to far lower number of conccurent workflows than expected
## Summary

Using a semaphore to limit the concurrent workflow executions leads to a far lower number of concurrent executions. I started 100 instances of a workflow limited to 6 concurrent executions using a semaphore. This was more-or-less taken from the argo examples. Interestingly in the beginning argo executed 6 Worflows in parallel, but after that dropped the number of concurrent executions of the workflow.

I logged the executions using a script and gnuplot and got this graph of concurrent executions over time:

![output](https://user-images.githubusercontent.com/140716/97180967-0bc8a280-179b-11eb-9da8-31e608ac030f.png)

The repetition of this test resulted in similar chart.

## Diagnostics

What Kubernetes provider are you using?

```
$ k version
Client Version: version.Info{Major:"1", Minor:"18", GitVersion:"v1.18.0", GitCommit:"9e991415386e4cf155a24b1da15becaa390438d8", GitTreeState:"clean", BuildDate:"2020-03-25T14:58:59Z", GoVersion:"go1.13.8", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"18", GitVersion:"v1.18.0", GitCommit:"9e991415386e4cf155a24b1da15becaa390438d8", GitTreeState:"clean", BuildDate:"2020-03-25T14:50:46Z", GoVersion:"go1.13.8", Compiler:"gc", Platform:"linux/amd64"}
```

What version of Argo Workflows are you running?

argo 2.11.5

Configmap used for semaphore:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
data:
  workflow: "6"
```

Workflow:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: synchronization-wf-level-
spec:
  entrypoint: whalesay
  synchronization:
    semaphore:
      configMapKeyRef:
        name: my-config
        key: workflow
  templates:
    - name: whalesay
      container:
        image: docker/whalesay:latest
        command: [cowsay]
        args: ["hello world"]
        imagePullPolicy: "IfNotPresent"

```

Logs  - these are just the last few lines, as I got 1.2Mb of logs for this. In case you need more to investigate this, I can provide more

```
time="2020-10-26T13:42:31Z" level=info msg="Processing workflow" namespace=gzs-default workflow=synchronization-wf-level-hpg6g
time="2020-10-26T13:42:31Z" level=info msg="Updating node synchronization-wf-level-hpg6g message: ContainerCreating"
time="2020-10-26T13:42:31Z" level=info msg="Skipped pod synchronization-wf-level-hpg6g (synchronization-wf-level-hpg6g) creation: already exists" namespace=gzs-default podPhase=Pending workflow=synchronization-wf-level-hpg6g
time="2020-10-26T13:42:31Z" level=info msg="Workflow update successful" namespace=gzs-default phase=Running resourceVersion=52456084 workflow=synchronization-wf-level-hpg6g
time="2020-10-26T13:42:32Z" level=info msg="Processing workflow" namespace=gzs-default workflow=synchronization-wf-level-hpg6g
time="2020-10-26T13:42:32Z" level=info msg="Updating node synchronization-wf-level-hpg6g status Pending -> Running"
time="2020-10-26T13:42:32Z" level=info msg="Workflow update successful" namespace=gzs-default phase=Running resourceVersion=52456099 workflow=synchronization-wf-level-hpg6g
time="2020-10-26T13:42:33Z" level=info msg="Processing workflow" namespace=gzs-default workflow=synchronization-wf-level-hpg6g
time="2020-10-26T13:42:33Z" level=info msg="Setting node synchronization-wf-level-hpg6g outputs"
time="2020-10-26T13:42:33Z" level=info msg="Updating node synchronization-wf-level-hpg6g status Running -> Succeeded"
time="2020-10-26T13:42:33Z" level=info msg="Updated phase Running -> Succeeded" namespace=gzs-default workflow=synchronization-wf-level-hpg6g
time="2020-10-26T13:42:33Z" level=info msg="Marking workflow completed" namespace=gzs-default workflow=synchronization-wf-level-hpg6g
time="2020-10-26T13:42:33Z" level=info msg="Checking daemoned children of " namespace=gzs-default workflow=synchronization-wf-level-hpg6g
time="2020-10-26T13:42:33Z" level=info msg="Lock has been released by gzs-default/synchronization-wf-level-hpg6g. Available locks: 6" semaphore=gzs-default/ConfigMap/my-config/workflow
time="2020-10-26T13:42:33Z" level=info msg="gzs-default/synchronization-wf-level-hpg6g released a lock from gzs-default/ConfigMap/my-config/workflow"
time="2020-10-26T13:42:33Z" level=info msg="Released all acquired locks" key=synchronization-wf-level-hpg6g
time="2020-10-26T13:42:33Z" level=info msg="Workflow update successful" namespace=gzs-default phase=Succeeded resourceVersion=52456104 workflow=synchronization-wf-level-hpg6g
time="2020-10-26T13:42:33Z" level=info msg="gzs-default/synchronization-wf-level-hpg6g released a lock from gzs-default/ConfigMap/my-config/workflow"
time="2020-10-26T13:42:33Z" level=info msg="Found Workflow gzs-default/synchronization-wf-level-hpg6g set expire at 2020-10-26 13:52:33 +0000 UTC (9m59.791764994s from now)"
time="2020-10-26T13:42:33Z" level=info msg="Queueing workflow gzs-default/synchronization-wf-level-hpg6g for delete in 9m59.791764994s"
time="2020-10-26T13:42:33Z" level=info msg="Found Workflow gzs-default/synchronization-wf-level-hpg6g set expire at 2020-10-26 13:52:33 +0000 UTC (9m59.791189794s from now)"
time="2020-10-26T13:42:33Z" level=info msg="Queueing workflow gzs-default/synchronization-wf-level-hpg6g for delete in 9m59.791189794s"
time="2020-10-26T13:42:34Z" level=info msg="gzs-default/ConfigMap/my-config/workflow acquired by gzs-default/synchronization-wf-level-rfv88 " semaphore=gzs-default/ConfigMap/my-config/workflow
time="2020-10-26T13:42:34Z" level=info msg="Processing workflow" namespace=gzs-default workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:34Z" level=info msg="Updated phase  -> Running" namespace=gzs-default workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:34Z" level=info msg="Pod node synchronization-wf-level-rfv88 initialized Pending" namespace=gzs-default workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:34Z" level=info msg="Created pod: synchronization-wf-level-rfv88 (synchronization-wf-level-rfv88)" namespace=gzs-default workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:34Z" level=info msg="Workflow update successful" namespace=gzs-default phase=Running resourceVersion=52456118 workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:34Z" level=info msg="Delete pod for gc successfully" namespace=gzs-default pod=synchronization-wf-level-hpg6g
time="2020-10-26T13:42:35Z" level=info msg="Processing workflow" namespace=gzs-default workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:35Z" level=info msg="Updating node synchronization-wf-level-rfv88 message: ContainerCreating"
time="2020-10-26T13:42:35Z" level=info msg="Skipped pod synchronization-wf-level-rfv88 (synchronization-wf-level-rfv88) creation: already exists" namespace=gzs-default podPhase=Pending workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:35Z" level=info msg="Workflow update successful" namespace=gzs-default phase=Running resourceVersion=52456128 workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:36Z" level=info msg="Processing workflow" namespace=gzs-default workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:36Z" level=info msg="Updating node synchronization-wf-level-rfv88 status Pending -> Running"
time="2020-10-26T13:42:36Z" level=info msg="Workflow update successful" namespace=gzs-default phase=Running resourceVersion=52456142 workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:37Z" level=info msg="Processing workflow" namespace=gzs-default workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:37Z" level=info msg="Setting node synchronization-wf-level-rfv88 outputs"
time="2020-10-26T13:42:37Z" level=info msg="Updating node synchronization-wf-level-rfv88 status Running -> Succeeded"
time="2020-10-26T13:42:37Z" level=info msg="Updated phase Running -> Succeeded" namespace=gzs-default workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:37Z" level=info msg="Marking workflow completed" namespace=gzs-default workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:37Z" level=info msg="Checking daemoned children of " namespace=gzs-default workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:37Z" level=info msg="Lock has been released by gzs-default/synchronization-wf-level-rfv88. Available locks: 6" semaphore=gzs-default/ConfigMap/my-config/workflow
time="2020-10-26T13:42:37Z" level=info msg="gzs-default/synchronization-wf-level-rfv88 released a lock from gzs-default/ConfigMap/my-config/workflow"
time="2020-10-26T13:42:37Z" level=info msg="Released all acquired locks" key=synchronization-wf-level-rfv88
time="2020-10-26T13:42:37Z" level=info msg="Workflow update successful" namespace=gzs-default phase=Succeeded resourceVersion=52456147 workflow=synchronization-wf-level-rfv88
time="2020-10-26T13:42:37Z" level=info msg="Found Workflow gzs-default/synchronization-wf-level-rfv88 set expire at 2020-10-26 13:52:37 +0000 UTC (9m59.698888772s from now)"
time="2020-10-26T13:42:37Z" level=info msg="Queueing workflow gzs-default/synchronization-wf-level-rfv88 for delete in 9m59.698888772s"
time="2020-10-26T13:42:37Z" level=info msg="gzs-default/synchronization-wf-level-rfv88 released a lock from gzs-default/ConfigMap/my-config/workflow"
time="2020-10-26T13:42:37Z" level=info msg="Found Workflow gzs-default/synchronization-wf-level-rfv88 set expire at 2020-10-26 13:52:37 +0000 UTC (9m59.698308465s from now)"
time="2020-10-26T13:42:37Z" level=info msg="Queueing workflow gzs-default/synchronization-wf-level-rfv88 for delete in 9m59.698308465s"
time="2020-10-26T13:42:38Z" level=info msg="Delete pod for gc successfully" namespace=gzs-default pod=synchronization-wf-level-rfv88

```

---
<!-- Issue Author: Don't delete this message to encourage other users to support your issue! -->
**Message from the maintainers**:

Impacted by this bug? Give it a 👍. We prioritise the issues with the most 👍.

### Additional contract requirements

The synchronization lock manager is created by the public function `NewLockManager(getSyncLimit func(string) (int, error), nextWorkflow func(string))` in package `workflow/sync`. `getSyncLimit` returns the maximum number of concurrent locks allowed for a given lock key, and `nextWorkflow` is the callback invoked with a workflow key when a waiting workflow can proceed.

`TryAcquire(wf *wfv1.Workflow, nodeName string, sync *wfv1.Synchronization) (status bool, wfUpdate bool, msg string, err error)` attempts to acquire the lock for the workflow. `status` is true when the lock is acquired and false otherwise. When acquisition fails, `msg` is a non-empty explanatory message.

`Release(wf *wfv1.Workflow, nodeName string, sync *wfv1.Synchronization)` releases the workflow's lock.

When a lock is released, the number of waiting workflows that are triggered to proceed equals the number of available locks (the semaphore limit minus the number of currently held locks), capped by the number of waiting workflows.


- A semaphore must not allow more workflows holding a lock at once than its configured limit. When a workflow releases its lock, that capacity must be available to a subsequent acquisition.
- An acquisition that cannot obtain a lock must report failure and include a non-empty explanation.
- When releasing a lock makes capacity available, waiting workflows must be notified using their workflow identity (namespace and name). Notify no more workflows than there are free lock slots or waiting workflows, whichever is fewer.
