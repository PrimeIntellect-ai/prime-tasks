List command doesn't return empty result in correct format
Hello,
we are working on a knative plugin for IntelliJ and we found out this misbehavior.

### Bug report

`list` command doesn't return empty result in correct format (json, yaml, .).

```
$ kn service list -o json
No services found.
```

### Expected behavior

I would expect it in json format
E.g
```
{
    "apiVersion": "serving.knative.dev/v1",
    "items": [],
    "kind": "Service",
    "metadata": {
        ...
    }
}
```

### Steps to reproduce the problem

Step above

### kn version

```
Version:      v0.21.0
Build Date:   2021-02-24 09:16:16
Git Revision: 5f68d612
Supported APIs:
* Serving
  - serving.knative.dev/v1 (knative-serving v0.21.0)
* Eventing
  - sources.knative.dev/v1alpha2 (knative-eventing v0.21.0)
  - eventing.knative.dev/v1beta1 (knative-eventing v0.21.0)
```

### Knative (serving/eventing) version

```
v0.21.0
```

### Additional contract requirements

When an output format is selected for an empty list, the output must be that format's representation of an empty list object, including its API version and an empty `items` array. For the service example, the `kind` must identify the service resource: either `Service` as shown in the example or `ServiceList` as a list kind is valid.
