Add `--scale-activation` flag to match new Serving option
<!-- If you need to report a security issue with Knative, send an email to knative-security@googlegroups.com. -->

### Feature request

Consider adding a new Ksvc flag to specify activation scale value. That represents number of replicas to be scaled from zero when service is activated.

Ref: https://github.com/knative/serving/pull/13161 (note it's an update PR to introduce new & current name of option)
https://github.com/knative/serving/pull/13136 (first PR with former name)

### UI Example



```
kn service create hello --image .../myapp --scale-activation 2
```

/kind good-first-issue

/cc @dprotaso @psschwei
<!--
Optional Classifications, remove the '> ' to select:
> /kind good-first-issue
> /kind proposal
> /kind doc
> /kind cleanup
-->
