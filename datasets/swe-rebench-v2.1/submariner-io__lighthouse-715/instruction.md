Submariner ServiceExport does not have unique condition types to wait for readiness
<!-- Please use this template while reporting a bug and provide as much info as
possible. Not doing so may result in your bug not being addressed in a timely
manner. Thanks!

If the matter is security related, please disclose it privately to the
Submariner Owners: https://github.com/orgs/submariner-io/teams/submariner-core
-->


**What happened**:
After creating service export with subctl, ther's no way to validate it with kubectl/oc wait command,
since Submariner ServiceExport does not have unique condition types to wait for readiness (all types are the same "Valid").

For example, on a working service export status it failed on:

$ oc wait serviceexport nginx-cl-bc --for=condition=Valid
error: timed out waiting for the condition on serviceexports/nginx-cl-bc


**What you expected to happen**:
If the service export is working, it should return something like:

multicluster.x-k8s.io/ServiceExportList condition met

**How to reproduce it (as minimally and precisely as possible)**:
Create a service export:
$ oc get serviceexport
NAME AGE
nginx-cl-bc 3h5m

$ oc get serviceexport -o yaml
apiVersion: v1
items:

apiVersion: multicluster.x-k8s.io/v1alpha1
kind: ServiceExport
metadata:
creationTimestamp: "2022-03-21T08:25:40Z"
generation: 1
name: nginx-cl-bc
namespace: test-submariner
resourceVersion: "115495575"
selfLink: /apis/multicluster.x-k8s.io/v1alpha1/namespaces/test-submariner/serviceexports/nginx-cl-bc
uid: 7af4a9ae-24f6-4d1d-9ac5-100664e03dd9
status:
conditions:
lastTransitionTime: "2022-03-21T08:25:39Z"
message: Service doesn't have a global IP yet
reason: ServiceGlobalIPUnavailable
status: "False"
type: Valid
lastTransitionTime: "2022-03-21T08:25:39Z"
message: Awaiting sync of the ServiceImport to the broker
reason: AwaitingSync
status: "False"
type: Valid
lastTransitionTime: "2022-03-21T08:25:39Z"
message: Service was successfully synced to the broker
reason: ""
status: "True"
type: Valid
lastTransitionTime: "2022-03-21T09:59:32Z"
message: Service to be exported doesn't exist
reason: ServiceUnavailable
status: "False"
type: Valid
lastTransitionTime: "2022-03-21T09:59:32Z"
message: Service doesn't have a global IP yet
reason: ServiceGlobalIPUnavailable
status: "False"
type: Valid
lastTransitionTime: "2022-03-21T09:59:33Z"
message: Awaiting sync of the ServiceImport to the broker
reason: AwaitingSync
status: "False"
type: Valid
lastTransitionTime: "2022-03-21T09:59:35Z"
message: Service was successfully synced to the broker
reason: ""
status: "True"
type: Valid
lastTransitionTime: "2022-03-21T10:20:16Z"
message: Service to be exported doesn't exist
reason: ServiceUnavailable
status: "False"
type: Valid
lastTransitionTime: "2022-03-21T10:20:16Z"
message: Service doesn't have a global IP yet
reason: ServiceGlobalIPUnavailable
status: "False"
type: Valid
kind: List
metadata:
resourceVersion: ""
selfLink: ""
$ oc wait serviceexport nginx-cl-bc --for=condition=Valid
error: timed out waiting for the condition on serviceexports/nginx-cl-bc


**Anything else we need to know?**:

**Environment**:
Submariner version 0.12.0

- Diagnose information (use `subctl diagnose all`):
- Gather information (use `subctl gather`):
- Cloud provider or hardware configuration:
- Install tools:
- Others:

### Additional contract requirements

- When a ServiceExport is working, its `Valid` condition has status `True`, so that `kubectl wait --for=condition=Valid` completes.
- Each condition type appears at most once in a ServiceExport's status conditions, so that a condition type identifies a single condition and a wait on it is not ambiguous.
