tekton controller fails on OpenShift 4.x
when trying to create a `PipelineRun` on OpenShift 4.x we get this error...

```
Failed to create pipeline run: pipelineruns.tekton.dev \"verify-vcszn\" is forbidden: cannot set blockOwnerDeletion if an ownerReference refers to a resource you can't set finalizers on
```

### Additional contract requirements

- When the controller creates a `PipelineRun` for a `LighthouseJob`, the `LighthouseJob` owner reference on that `PipelineRun` must leave `blockOwnerDeletion` unset (nil). It is not sufficient to set the field to `false`: the field must be absent from the created `PipelineRun`.
