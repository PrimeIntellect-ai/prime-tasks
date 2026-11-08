kn trigger create fails without --filter flag
<!-- If you need to report a security issue with Knative, send an email to knative-security@googlegroups.com. -->

### Bug report

There was a bug in Eventing 0.13.0 that rejected triggers without filters. However, even on version `0.13.1` the creation of such trigger will fail. There's a bug in our current impl that will [HIDDEN] that causes the error behaviour.

Beware, that `kn trigger describe` has to be fixed for empty filters also.

```bash
$ kn trigger create test --broker default --sink svc:svc1
cannot create trigger 'test' in namespace 'default' because: admission webhook "validation.webhook.eventing.knative.dev" denied the request: validation failed: At least one filtered attribute must be specified: spec.filter.attributes
```

### Expected behavior

Trigger can be created without `--filter` flag.

### Steps to reproduce the problem

1. kn trigger create test --broker default --sink svc:svc1


<!-- How can a maintainer reproduce this issue (please be detailed) -->

### kn version

HEAD

### Knative (serving/eventing) version

0.13.1

/kind good-first-issue

### Additional contract requirements

A trigger created without filter criteria must not contain filter attributes, whether the filter input is omitted, nil, or empty. Describing a trigger with no filter or with an empty filter must complete without an error.
