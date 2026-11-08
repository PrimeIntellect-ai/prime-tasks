Retryable tasks with template-level metrics are falsely labelled as Running
## Summary

When using a metric label value of `{{status}}` I expected a status like `Failed` or `Succeeded`. However, when a retryStrategy is defined on the task, the metric ends up having a label value of `Running`.

## Diagnostics

What Kubernetes provider are you using? Google Kubernetes Engine (GKE).

What version of Argo Workflows are you running? 2.12.3

`kube get wf -o yaml metrics-eg-j6w2z`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  creationTimestamp: "2021-01-08T05:48:52Z"
  generateName: metrics-eg-
  generation: 3
  labels:
    workflows.argoproj.io/completed: "true"
    workflows.argoproj.io/phase: Succeeded
  name: metrics-eg-j6w2z
  namespace: argo
  resourceVersion: "189179375"
  selfLink: /apis/argoproj.io/v1alpha1/namespaces/argo/workflows/metrics-eg-j6w2z
  uid: b07a727a-4913-411b-8877-05e619f2751f
spec:
  arguments: {}
  entrypoint: my-dag
  serviceAccountName: argo
  templates:
  - arguments: {}
    dag:
      tasks:
      - arguments: {}
        name: A
        template: A
    inputs: {}
    metadata: {}
    name: my-dag
    outputs: {}
  - arguments: {}
    container:
      args:
      - hello from A
      command:
      - cowsay
      image: docker/whalesay
      name: ""
      resources: {}
    inputs: {}
    metadata:
      annotations:
        sidecar.istio.io/inject: "false"
    metrics:
      prometheus:
      - counter:
          value: "1"
        help: Number of argo workflows
        labels:
        - key: work_unit
          value: metrics-eg::A
        - key: workflow_result
          value: '{{status}}'
        name: result_counter
    name: A
    outputs: {}
    retryStrategy:
      backoff:
        duration: 2s
        factor: 1
        maxDuration: 6m
      limit: 2
      retryPolicy: Always
status:
  conditions:
  - status: "True"
    type: Completed
  finishedAt: "2021-01-08T05:49:02Z"
  nodes:
    metrics-eg-j6w2z:
      children:
      - metrics-eg-j6w2z-1803019796
      displayName: metrics-eg-j6w2z
      finishedAt: "2021-01-08T05:49:02Z"
      id: metrics-eg-j6w2z
      name: metrics-eg-j6w2z
      outboundNodes:
      - metrics-eg-j6w2z-2894961471
      phase: Succeeded
      progress: 1/1
      resourcesDuration:
        cpu: 1
        memory: 1
      startedAt: "2021-01-08T05:48:52Z"
      templateName: my-dag
      templateScope: local/metrics-eg-j6w2z
      type: DAG
    metrics-eg-j6w2z-1803019796:
      boundaryID: metrics-eg-j6w2z
      children:
      - metrics-eg-j6w2z-2894961471
      displayName: A
      finishedAt: "2021-01-08T05:49:02Z"
      id: metrics-eg-j6w2z-1803019796
      name: metrics-eg-j6w2z.A
      outputs:
        exitCode: "0"
      phase: Succeeded
      progress: 1/1
      resourcesDuration:
        cpu: 1
        memory: 1
      startedAt: "2021-01-08T05:48:52Z"
      templateName: A
      templateScope: local/metrics-eg-j6w2z
      type: Retry
    metrics-eg-j6w2z-2894961471:
      boundaryID: metrics-eg-j6w2z
      displayName: A(0)
      finishedAt: "2021-01-08T05:48:55Z"
      id: metrics-eg-j6w2z-2894961471
      name: metrics-eg-j6w2z.A(0)
      outputs:
        exitCode: "0"
      phase: Succeeded
      progress: 1/1
      resourcesDuration:
        cpu: 1
        memory: 1
      startedAt: "2021-01-08T05:48:52Z"
      templateName: A
      templateScope: local/metrics-eg-j6w2z
      type: Pod
  phase: Succeeded
  progress: 1/1
  resourcesDuration:
    cpu: 1
    memory: 1
  startedAt: "2021-01-08T05:48:52Z"
```

`kubectl logs -n argo $(kubectl get pods -l app=workflow-controller -n argo -o name) | grep metrics-eg-j6w2z`
```
time="2021-01-08T05:48:52.575Z" level=info msg="Processing workflow" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:48:52.575Z" level=info msg="Updated phase  -> Running" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:48:52.576Z" level=info msg="DAG node metrics-eg-j6w2z initialized Running" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:48:52.576Z" level=info msg="All of node metrics-eg-j6w2z.A dependencies [] completed" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:48:52.577Z" level=info msg="Retry node metrics-eg-j6w2z-1803019796 initialized Running" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:48:52.577Z" level=info msg="Pod node metrics-eg-j6w2z-2894961471 initialized Pending" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:48:52.603Z" level=info msg="Created pod: metrics-eg-j6w2z.A(0) (metrics-eg-j6w2z-2894961471)" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:48:52.609Z" level=info msg="Workflow update successful" namespace=argo phase=Running resourceVersion=189179261 workflow=metrics-eg-j6w2z
time="2021-01-08T05:49:02.604Z" level=info msg="Processing workflow" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:49:02.605Z" level=info msg="Setting node metrics-eg-j6w2z-2894961471 outputs"
time="2021-01-08T05:49:02.605Z" level=info msg="Updating node metrics-eg-j6w2z-2894961471 status Pending -> Succeeded"
time="2021-01-08T05:49:02.605Z" level=info msg="node metrics-eg-j6w2z-1803019796 phase Running -> Succeeded" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:49:02.605Z" level=info msg="node metrics-eg-j6w2z-1803019796 finished: 2021-01-08 05:49:02.605855624 +0000 UTC" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:49:02.606Z" level=info msg="Outbound nodes of metrics-eg-j6w2z set to [metrics-eg-j6w2z-2894961471]" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:49:02.606Z" level=info msg="node metrics-eg-j6w2z phase Running -> Succeeded" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:49:02.606Z" level=info msg="node metrics-eg-j6w2z finished: 2021-01-08 05:49:02.606084969 +0000 UTC" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:49:02.606Z" level=info msg="Checking daemoned children of metrics-eg-j6w2z" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:49:02.606Z" level=info msg="Updated phase Running -> Succeeded" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:49:02.606Z" level=info msg="Marking workflow completed" namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:49:02.606Z" level=info msg="Checking daemoned children of " namespace=argo workflow=metrics-eg-j6w2z
time="2021-01-08T05:49:02.614Z" level=info msg="Workflow update successful" namespace=argo phase=Succeeded resourceVersion=189179375 workflow=metrics-eg-j6w2z
time="2021-01-08T05:49:02.625Z" level=info msg="Labeled pod completed" namespace=argo pod=metrics-eg-j6w2z-2894961471
```

---
<!-- Issue Author: Don't delete this message to encourage other users to support your issue! -->
**Message from the maintainers**:

Impacted by this bug? Give it a 👍. We prioritise the issues with the most 👍.
