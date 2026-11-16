Automatically inject ownerReferences
Inject [`metadata.ownerReferences`](https://kubernetes.io/docs/concepts/workloads/controllers/garbage-collection/) into resources.

I'm not positive the [original idea](#original-idea) below will work. Middleware is per cluster and it would need a per resource data to inject ownerReference.

Definitely worth looking into, but a simple solution for now could be to add an `add_owner_references/2` function to the Controller behavior.

```elixir
def added(todo = %{}) do
  %K8s.Operation{} # make an operation
  |> add_owner_references(todo) # attached `todo` crd references
  |> K8s.run(conn)
end
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  ...
  ownerReferences:
  - apiVersion: apps/v1
    controller: true
    blockOwnerDeletion: true
    kind: ReplicaSet
    name: my-repset
    uid: d9607e19-f88f-11e6-a518-42010a800195
  ...
```
---

### original idea

This will require
* [x] [`K8s.Middleware`](https://github.com/coryodaniel/k8s/issues/42) to modify all JSON paylaods during a lifecycle event
* [ ] Ensure lifecycle events are dispatched in their own process
* [ ] Store custom resource's information by process ID so that it can be fetched by middleware
* [ ] default implementation to make the delete lifecycle a no-op as deletion should happen via k8s/ownerReferences garbage collection

Related #79

### Additional contract requirements

- Add a public function `Bonny.Controller.add_owner_reference(resource, owner, opts \\ [])` that returns `resource` with an `ownerReferences` entry added under its `metadata`.
- `owner` is a map with string keys `"apiVersion"`, `"kind"`, and `"metadata"` containing `"name"` and `"uid"`. The generated reference is a map containing the owner's `"apiVersion"`, `"kind"`, `"name"` and `"uid"`, together with `"controller" => true` and `"blockOwnerDeletion"`.
- `opts` accepts `block_owner_deletion: boolean` (default `false`); when it is `true`, the generated reference's `"blockOwnerDeletion"` is `true`.
- `resource` may use string keys or atom keys, and the returned map keeps the same key style as the input.
- If `metadata.ownerReferences` already exists, the new reference is added without removing or overwriting the references already present.
