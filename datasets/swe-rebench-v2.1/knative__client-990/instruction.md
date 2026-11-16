Add support for --scale-init
Now that we have support for defining the initial scale for a service, it would be nice if `kn` supported it via a top-level option instead of just as an annotation.

e.g.
kn service create echo --image duglin/echo --annotation autoscaling.knative.dev/initialScale=0
vs
kn service create echo --image duglin/echo --scale-init=0

or --scale-initial

### Additional contract requirements

- If both `--scale-init` and `--annotation autoscaling.knative.dev/initialScale` are specified, the command must fail with an error message containing `only one of the --scale-init or --annotation autoscaling.knative.dev/initialScale can be specified`.
- Service update must also accept `--scale-init` and apply its supplied value as the service's initial scale.
