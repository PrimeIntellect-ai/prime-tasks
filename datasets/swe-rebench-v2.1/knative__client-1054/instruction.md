Add WithLabel list filter to serving client lib
<!-- If you need to report a security issue with Knative, send an email to knative-security@googlegroups.com. -->

### Feature request

The list filters in serving client lib are missing an option to filter by specified label, eg. something similar that could be achieved by this call:
```go
servingClient.Services(l.namespace).List(metav1.ListOptions{LabelSelector: labelSelector})
```

Serving Client lib:
https://github.com/knative/client/blob/b13cd70490587f22ec88831d657c0daf38ed4308/pkg/serving/v1/client.go#L110-L142

Would be nice to add `func WithLabel(labelKey, labelValue string) ListConfig`

<!--
Optional Classifications, remove the '> ' to select:
> /kind good-first-issue
 /kind proposal
> /kind doc
> /kind cleanup
-->
