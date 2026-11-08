Workflow Archive RBAC doesn't agree with Workflow / Timeline RBAC
Checklist:

 * [x] I've included the version.
 * [ ] I've included reproduction steps.
 * [ ] I've included the workflow YAML.
 * [x] I've included the logs.

**What happened**:
For context, I'm running the Argo Server in hosted mode, with the "client" auth mode enabled. The SA running the server has minimal RBAC (get/watch/list on configmaps and get on secrets).

Workflows are being written to the `argo_archived_workflows` table by my controller, but the Archived Workflows page in the UI claims there are none in the DB. Looking in the logs I found:
```
time="2020-03-09T13:32:52Z" level=debug msg=CanI allowed=false name=clinvar-ingest-pwnpk namespace=clinvar resource=workflows verb=get
```
Emphasis on `allowed=false`. This was confusing because the Timeline page makes the same call to decide what should be shown, and workflows have been appearing there without problems.

**What you expected to happen**:
All workflows in the archive table appear in the UI when using client-mode auth as a user with sufficient permissions.

**Anything else we need to know?**:
I found that the server is filtering archived workflows returned by the DB using a `can-i` call [here](https://github.com/argoproj/argo/blob/master/server/workflowarchive/archived_workflow_server.go#L73). When I run the command locally, it works:
```
$ kubectl -n clinvar auth can-i get workflow/clinvar-ingest-pwnpk
yes
```
Could the workflow archive API be dropping / ignoring the auth-mode config, always using the equivalent of server mode?

**Environment**:
- Argo version:
```
$ argo version
argo: v2.6.0
  BuildDate: 2020-02-28T23:32:45Z
  GitCommit: 5d3bdd56607eea962183a9e45009e3d08fafdf9b
  GitTreeState: clean
  GitTag: v2.6.0
  GoVersion: go1.13.4
  Compiler: gc
  Platform: darwin/amd64
```
I'm running 2.6.1 for the server / controller.
- Kubernetes version :
```
$ kubectl version -o yaml
clientVersion:
  buildDate: "2020-01-18T23:33:14Z"
  compiler: gc
  gitCommit: 2e808b7cb054ee242b68e62455323aa783991f03
  gitTreeState: clean
  gitVersion: v1.15.9
  goVersion: go1.12.12
  major: "1"
  minor: "15"
  platform: darwin/amd64
serverVersion:
  buildDate: "2020-01-29T19:27:22Z"
  compiler: gc
  gitCommit: 2ccf2c797713077f4a3d0f87c4b4bae725362326
  gitTreeState: clean
  gitVersion: v1.15.8-gke.3
  goVersion: go1.12.12b4
  major: "1"
  minor: 15+
  platform: linux/amd64
```

---
<!-- Issue Author: Don't delete this message to ecourage other users to support your issue! -->
**Message from the maintainers**:

If you are impacted by this bug please add a 👍 reaction to this issue! We often sort issues this way to know what to prioritize.

### Additional contract requirements

- When a caller lacks permission to list archived workflows, the request must return gRPC status `PermissionDenied` with message `permission denied` (HTTP 403).
