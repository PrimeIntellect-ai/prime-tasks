"options" adding resource entries on multiple installersets
it is possible to create `HPA` and `ConfigMap` via `options` [1]
I was not aware of multiple installersets creation for a component at the time of `options` implementation.
I see, Two type of installersets [2] created for pipelines component,
1. deployment only
2. static - all others (except deployment)

The `options` transformer called two times via transformer[3].
Assume user provided a details to update a existing HPA resource.
first the transformer called with only deployments manifests,
* checks HPA resource
* HPA resource not available
* Creates HPA resource and adding in that manifest (deployments manifests)

second time the transformer called with static manifests(except deployments)
* checks HPA resource
* HPA resource found
* updates HPA resource on the manifest

Now we have the same HPA resource on two installersets. This leads race condition and malfunction.

[1] - https://tekton.dev/docs/operator/tektonconfig/#additional-fields-as-options
[2] - https://github.com/tektoncd/operator/blob/2754ea9e1bcf7fd74cb55d4faf6f993c5f1fbe16/pkg/reconciler/kubernetes/tektoninstallerset/client/create.go#L61-L62
[3] - https://github.com/tektoncd/operator/blob/2754ea9e1bcf7fd74cb55d4faf6f993c5f1fbe16/pkg/reconciler/kubernetes/tektonpipeline/transform.go#L55 https://github.com/tektoncd/operator/blob/2754ea9e1bcf7fd74cb55d4faf6f993c5f1fbe16/pkg/reconciler/kubernetes/tektonpipeline/transform.go#L88

### Additional contract requirements

- When options update an existing `HorizontalPodAutoscaler`, an omitted `minReplicas` keeps the existing minimum and `maxReplicas: 0` keeps the existing maximum. Explicitly supplied values, including `minReplicas: 2` and `maxReplicas: 9`, are applied.
- Options must not add a `HorizontalPodAutoscaler` that does not already exist in the manifest. An HPA listed in options with no matching HPA in the manifest is left out, so the same HPA is never placed in more than one installer set.
