[HIDDEN]
/kind bug
When working on https://github.com/kubernetes/kubernetes/pull/91591 we noticed that
```
klog.V(2).InfoS("NODE DENY", "err", err)
```
was serialized to
```
I0603 09:57:29.759232   53238 node_authorizer.go:209] "NODE DENY" err=&errors.errorString{s:"node \"node2\" cannot get secret ns1/node1-only, no relationship to this object was found in the node authorizer graph"}
```
instead of
```
I0603 09:57:29.759232   53238 node_authorizer.go:209] "NODE DENY" err="node \"node2\" cannot get secret ns1/node1-only, no relationship to this object was found in the node authorizer graph"
```

Possibly it was fixed by https://github.com/kubernetes/klog/issues/156
If so we should  add tests for Error objects.

### Additional contract requirements

- When `InfoS` receives an error-valued key/value pair, render the error text as a quoted string rather than as a Go-syntax representation.
