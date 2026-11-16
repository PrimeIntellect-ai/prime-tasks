Integers are no longer supported in parameters
## Summary

What happened/what you expected to happen?

When we have a workflow template with a parameter that can be an integer we get the following error `cannot unmarshall spec: cannot convert int64 to v1alpha1.Int64OrString`.

Integers were supported in 2.10 and it no longer works with 2.11.6 (only 2.11 version I've tested)

## Diagnostics

What Kubernetes provider are you using?
1.19

What version of Argo Workflows are you running?
2.11.6

The workflow I ran
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: hello-world-parameters-
spec:
  entrypoint: whalesay
  arguments:
    parameters:
    - name: message
      value: Your age is
    - name: age
      value: 30
    - name: image
      value: docker/whalesay

  templates:
  - name: whalesay
    inputs:
      parameters:
      - name: message
      - name: age
      - name: image
    container:
      image: "{{inputs.parameters.image}}"
      command: [cowsay]
      args: ["{{inputs.parameters.message}} {{inputs.parameters.age}}"]
```

The workflow object created
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  creationTimestamp: "2020-10-23T15:24:47Z"
  generateName: hello-world-parameters-
  generation: 2
  labels:
    workflows.argoproj.io/completed: "true"
    workflows.argoproj.io/phase: Failed
  managedFields:
  - apiVersion: argoproj.io/v1alpha1
    fieldsType: FieldsV1
    fieldsV1:
      f:metadata:
        f:generateName: {}
      f:spec:
        .: {}
        f:arguments: {}
        f:entrypoint: {}
        f:templates: {}
      f:status: {}
    manager: argo
    operation: Update
    time: "2020-10-23T15:24:47Z"
  - apiVersion: argoproj.io/v1alpha1
    fieldsType: FieldsV1
    fieldsV1:
      f:metadata:
        f:labels:
          .: {}
          f:workflows.argoproj.io/completed: {}
          f:workflows.argoproj.io/phase: {}
      f:spec:
        f:arguments:
          f:parameters: {}
      f:status:
        f:conditions: {}
        f:finishedAt: {}
        f:message: {}
        f:phase: {}
        f:startedAt: {}
    manager: workflow-controller
    operation: Update
    time: "2020-10-23T15:24:47Z"
  name: hello-world-parameters-sjqh9
  namespace: argo
  resourceVersion: "735"
  selfLink: /apis/argoproj.io/v1alpha1/namespaces/argo/workflows/hello-world-parameters-sjqh9
  uid: 252f88a7-f24d-4270-9a96-b9e6e71ecc32
spec:
  arguments:
    parameters:
    - name: message
      value: Your age is
    - name: age
      value: ""
    - name: ""
  entrypoint: whalesay
  templates:
  - arguments: {}
    container:
      args:
      - '{{inputs.parameters.message}} {{inputs.parameters.age}}'
      command:
      - cowsay
      image: '{{inputs.parameters.image}}'
      name: ""
      resources: {}
    inputs:
      parameters:
      - name: message
      - name: age
      - name: image
    metadata: {}
    name: whalesay
    outputs: {}
status:
  conditions:
  - status: "True"
    type: Completed
  finishedAt: "2020-10-23T15:24:47Z"
  message: 'cannot unmarshall spec: cannot convert int64 to v1alpha1.Int64OrString'
  phase: Failed
  startedAt: "2020-10-23T15:24:47Z"
```
Paste the logs from the workflow controller:
```
time="2020-10-23T15:24:47Z" level=warning msg="Failed to unmarshal key to workflow object" error="cannot convert int64 to v1alpha1.Int64OrString" key=argo/hello-world-parameters-sjqh9
time="2020-10-23T15:24:47Z" level=info msg="Updated phase  -> Failed" namespace=argo workflow=hello-world-parameters-sjqh9
time="2020-10-23T15:24:47Z" level=info msg="Updated message  -> cannot unmarshall spec: cannot convert int64 to v1alpha1.Int64OrString" namespace=argo workflow=hello-world-parameters-sjqh9
time="2020-10-23T15:24:47Z" level=info msg="Marking workflow completed" namespace=argo workflow=hello-world-parameters-sjqh9
time="2020-10-23T15:24:47Z" level=warning msg="Invalid workflow object" key="&{map[apiVersion:argoproj.io/v1alpha1 kind:Workflow metadata:map[creationTimestamp:2020-10-23T15:24:47Z generateName:hello-world-parameters- generation:1 managedFields:[map[apiVersion:argoproj.io/v1alpha1 fieldsType:FieldsV1 fieldsV1:map[f:metadata:map[f:generateName:map[]] f:spec:map[.:map[] f:arguments:map[.:map[] f:parameters:map[]] f:entrypoint:map[] f:templates:map[]] f:status:map[.:map[] f:finishedAt:map[] f:startedAt:map[]]] manager:argo operation:Update time:2020-10-23T15:24:47Z]] name:hello-world-parameters-sjqh9 namespace:argo resourceVersion:734 selfLink:/apis/argoproj.io/v1alpha1/namespaces/argo/workflows/hello-world-parameters-sjqh9 uid:252f88a7-f24d-4270-9a96-b9e6e71ecc32] spec:map[arguments:map[parameters:[map[name:message value:Your age is] map[name:age value:30] map[name:image value:docker/whalesay]]] entrypoint:whalesay templates:[map[arguments:map[] container:map[args:[{{inputs.parameters.message}} {{inputs.parameters.age}}] command:[cowsay] image:{{inputs.parameters.image}} name: resources:map[]] inputs:map[parameters:[map[name:message] map[name:age] map[name:image]]] metadata:map[] name:whalesay outputs:map[]]]] status:map[finishedAt:<nil> startedAt:<nil>]]}"
time="2020-10-23T15:24:47Z" level=info msg="Workflow update successful" namespace=argo phase=Failed resourceVersion=735 workflow=hello-world-parameters-sjqh9
```

I get the same issue if the parameter **age** has a default integer value (say 30) and I don't pass it to the workflow template
---
<!-- Issue Author: Don't delete this message to encourage other users to support your issue! -->
**Message from the maintainers**:

Impacted by this bug? Give it a 👍. We prioritise the issues with the most 👍.

### Additional contract requirements

The public function `FromUnstructured(un *unstructured.Unstructured) (*wfv1.Workflow, error)` in package `workflow/util` must tolerate integer parameter values when decoding a workflow, both for supplied workflow arguments (`spec.arguments.parameters`) and for parameter defaults (`spec.templates[].inputs.parameters`).


- When `workflow/util.FromUnstructured` decodes these integer values, it must represent the supplied argument `30` and parameter default `20` as string-valued `Int64OrString` values: `"30"` and `"20"`.
