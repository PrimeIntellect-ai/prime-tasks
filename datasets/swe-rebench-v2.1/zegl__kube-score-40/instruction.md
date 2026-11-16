Container image pull policy is asking for an invalid value
My YAML container image pull policy says:
 imagePullPolicy: Always

and kube-core is recommending "PullAlways" value
[CRITICAL] Container Image Pull Policy
        * esp -> ImagePullPolicy is not set to PullAlways
             It's recommended to always set the ImagePullPolicy to PullAlways, to make sure that the imagePullSecrets are always correct, and to always get the image you want.

however, that is not a valid value according to latest API definition:
https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.12/

Image pull policy. One of Always, Never, IfNotPresent. Defaults to Always if :latest tag is specified, or IfNotPresent otherwise. Cannot be updated. More info: https://kubernetes.io/docs/concepts/containers/images#updating-images

### Additional contract requirements

The pull-policy recommendation must name the valid Kubernetes value `Always`, not `PullAlways`. When `imagePullPolicy` is omitted, account for Kubernetes defaults: an image explicitly tagged `:latest` or an image with no tag defaults to `Always`; an image with a non-`latest` tag defaults to `IfNotPresent` and does not satisfy a recommendation for `Always`.
