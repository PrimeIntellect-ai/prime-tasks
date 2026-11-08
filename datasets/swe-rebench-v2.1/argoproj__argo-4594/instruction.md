WorkflowEventBinding passes raw go structs instead of json marshalled payload params
## Summary

What happened/what you expected to happen?
Creating a simple WorkflowEventBinding for github that triggers workflows based on certain labels in PR.

Doing payload.pull_request.labels gives me a full go struct rather than a json object. Go structs aren't very useful since the lingua franca of the web is json. I can't easily pipe this into a python container and do something with labels.

## Diagnostics

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  annotations:
    owner: core
  labels: {}
  name: deploy-pr
  namespace: github
spec:
  arguments:
    artifacts: []
    parameters:
    - name: action
      value: ''
    - name: pr_author
      value: ''
    - name: pr_branch
      value: ''
    - name: pr_commit
      value: ''
    - name: pr_labels
      value: ''
    - name: pr_num
      value: ''
  entrypoint: deploy-pr
  templates:
  - container:
      args:
      - '{{workflow.parameters}}'
      command:
      - echo
      image: ubuntu:latest
      imagePullPolicy: IfNotPresent
    name: print
  - dag:
      tasks:
      - arguments:
          artifacts: []
          parameters: []
        name: trigger-workflow
        template: print
    name: deploy-pr
  volumes: []
  workflowMetadata:
    annotations:
      owner: core
    labels: {}
---
apiVersion: argoproj.io/v1alpha1
kind: WorkflowEventBinding
metadata:
  annotations:
    owner: core
  labels: {}
  name: deploy-pr
  namespace: github
spec:
  event:
    selector: metadata["x-github-event"] == ["pull_request"] && any(payload.pull_request.labels,
      {.name == "stage-and-deploy"})
  submit:
    arguments:
      parameters:
      - name: action
        valueFrom:
          event: payload.action
      - name: pr_author
        valueFrom:
          event: payload.pull_request.user.login
      - name: pr_branch
        valueFrom:
          event: payload.pull_request.head.ref
      - name: pr_commit
        valueFrom:
          event: payload.pull_request.head.sha
      - name: pr_labels
        valueFrom:
          event: payload.pull_request.labels
      - name: pr_num
        valueFrom:
          event: payload.number
    workflowTemplateRef:
      name: deploy-pr

```

What version of Argo Workflows are you running?  v2.11.5

The output is

```json
[
  {
    "name": "action",
    "value": "labeled"
  },
  {
    "name": "pr_author",
    "value": "nojvek"
  },
  {
    "name": "pr_branch",
    "value": "nojvek-test"
  },
  {
    "name": "pr_commit",
    "value": "f2116e4139e9ef8827f65b76293890e594f0fdcb"
  },
  {
    "name": "pr_labels",
    "value": "[map[color:0052cc default:false description:Only deploy configmaps id:2.442548891e+09 name:configmaps-only node_id:MDU6TGFiZWwyNDQyNTQ4ODkx url:https://api.github.com/repos/mixpanel/analytics/labels/configmaps-only] map[color:1d76db default:false description:Don't wait for user QA, if staging workflow succeeds, deploy to prod id:2.514491821e+09 name:skip-qa-confirm node_id:MDU6TGFiZWwyNTE0NDkxODIx url:https://api.github.com/repos/mixpanel/analytics/labels/skip-qa-confirm] map[color:5319e7 default:false description:Stage to staging-1, then deploy to production id:2.442682022e+09 name:stage-and-deploy node_id:MDU6TGFiZWwyNDQyNjgyMDIy url:https://api.github.com/repos/mixpanel/analytics/labels/stage-and-deploy] map[color:0052cc default:false description: id:2.292237044e+09 name:webapp/nginx node_id:MDU6TGFiZWwyMjkyMjM3MDQ0 url:https://api.github.com/repos/mixpanel/analytics/labels/webapp/nginx]]"
  },
  {
    "name": "pr_num",
    "value": "33195"
  }
]
```

The core issue is I'd expect the payload.pull_request.labels to be json marshalled, rather than go debug output e.g `[map[color:0052cc `


---
<!-- Issue Author: Don't delete this message to encourage other users to support your issue! -->
**Message from the maintainers**:

Impacted by this bug? Give it a 👍. We prioritise the issues with the most 👍.

### Additional contract requirements

- Parameter values selected from the event payload (via `valueFrom.event`) are JSON-marshalled before being stored on the submitted workflow. A structured value such as the map `{"bar":"baz"}` is stored as the compact JSON text `{"bar":"baz"}`, not Go debug output such as `map[bar:baz]`.
- String values are stored without surrounding quotes: the expression `"bar"` yields the parameter value `bar`.
