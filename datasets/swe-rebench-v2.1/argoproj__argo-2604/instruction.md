CronWorkflow does not work with controller-instanceid
Checklist:

 * [x] I've included the version.
 * [x] I've included reproduction steps.
 * [x] I've included the workflow YAML.
 * [x] I've included the logs.

**What happened**:
The workflow controller panic when starting cron workflow with label `workflows.argoproj.io/controller-instanceid` since `2.7.0`

**What you expected to happen**:
The Workflow should run

**How to reproduce it (as minimally and precisely as possible)**:
Add the following `CronWorkflow`

```
apiVersion: argoproj.io/v1alpha1
kind: CronWorkflow
metadata:
  name: hello-world
  labels:
    workflows.argoproj.io/controller-instanceid: test-controller
spec:
  schedule: "* * * * *"
  workflowMetadata:
    labels:
      label1: value1
    annotations:
      annotation2: value2
  workflowSpec:
    entrypoint: whalesay
    templates:
      - name: whalesay
        container:
          image: docker/whalesay:latest
          command: [cowsay]
          args: ["hello world"]
```
**Anything else we need to know?**:

**Environment**:
- Argo version: 2.7.0
```
argo: v2.7.0
  BuildDate: 2020-03-31T23:35:04Z
  GitCommit: 4d1175eb68f6578ed5d599f877be9b4855d33ce9
  GitTreeState: clean
  GitTag: v2.7.0
  GoVersion: go1.13.4
  Compiler: gc
  Platform: linux/amd64
```
- Kubernetes version :
```
serverVersion:
  buildDate: "2020-01-31T20:00:26Z"
  compiler: gc
  gitCommit: c52f59bbba5fbf21fbb18e9a06f96e563fe4c20a
  gitTreeState: clean
  gitVersion: v1.14.8
  goVersion: go1.12.10
  major: "1"
  minor: "14"
  platform: linux/amd64
```

**Other debugging information (if applicable)**:
[HIDDEN]
github.com/argoproj/argo/workflow/common.ConvertCronWorkflowToWorkflow(0xc0009f6380, 0x1)
        /go/src/github.com/argoproj/argo/workflow/common/convert.go:11 +0x8b0
github.com/argoproj/argo/workflow/cron.(*cronWfOperationCtx).Run(0xc000dbcf00)
        /go/src/github.com/argoproj/argo/workflow/cron/operator.go:59 +0x229
github.com/robfig/cron/v3.(*Cron).startJob.func1(0xc0000b8dc0, 0x1a5a5e0, 0xc000dbcf00)
        /go/pkg/mod/github.com/robfig/cron/v3@v3.0.1/cron.go:312 +0x69
created by github.com/robfig/cron/v3.(*Cron).startJob
        /go/pkg/mod/github.com/robfig/cron/v3@v3.0.1/cron.go:310 +0x73
```

[HIDDEN]
github.com/argoproj/argo/workflow/common.ConvertCronWorkflowToWorkflow(0xc0009f6380, 0x1)
        /go/src/github.com/argoproj/argo/workflow/common/convert.go:11 +0x8b0
github.com/argoproj/argo/workflow/cron.(*cronWfOperationCtx).Run(0xc000dbcf00)
        /go/src/github.com/argoproj/argo/workflow/cron/operator.go:59 +0x229
github.com/robfig/cron/v3.(*Cron).startJob.func1(0xc0000b8dc0, 0x1a5a5e0, 0xc000dbcf00)
        /go/pkg/mod/github.com/robfig/cron/v3@v3.0.1/cron.go:312 +0x69
created by github.com/robfig/cron/v3.(*Cron).startJob
        /go/pkg/mod/github.com/robfig/cron/v3@v3.0.1/cron.go:310 +0x73
```

---
<!-- Issue Author: Don't delete this message to ecourage other users to support your issue! -->
**Message from the maintainers**:

If you are impacted by this bug please add a 👍 reaction to this issue! We often sort issues this way to know what to prioritize.

### Additional contract requirements

- Starting a scheduled run for a CronWorkflow with the `workflows.argoproj.io/controller-instanceid` metadata label must not panic, and the resulting Workflow must be able to run.
- The resulting Workflow must retain that label with the same value.
