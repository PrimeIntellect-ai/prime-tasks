autoscaling annotations must be put under "spec.template.metadata.annotations" to work
In client, we set (all) the annotations to service metadata annos as well as template metadata annotations.
see https://github.com/knative/client/blob/1607bf8c0c6404632d203f5a8794ac60d7c7659c/pkg/serving/config_changes.go#L457

With https://github.com/knative/serving/pull/9358 serving now validates the autoscaling related annotations, we'd need to stop setting the respective annotations at service metadata and only set for template metadata. The change in serving landed in master and would be part of v0.18.0 , so we'll need this for client v0.18.0 and probably backport to v0.17.x as well ? (cc: @rhuss )

The fix should be made in a manner to consider this related feature request https://github.com/knative/client/issues/1014
