Implement klog.KObj klog.KRef functions
/kind feature

**Describe the solution you'd like**
Klog should implement standard klog.KObj and klog.KRef functions needed for referencing kubernetes objects.

```go
func KObj(obj ObjectMeta) ObjectRef
func KRef(namespace, name string) ObjectRef

type ObjectRef struct {
  Name      string `json:"name"`
  Namespace string `json:"namespace,omitempty"`
}
```

Specifications are described within [KEP](https://github.com/kubernetes/enhancements/blob/master/keps/sig-instrumentation/20191115-structured-logging.md#new-klog-methods)

**Anything else you would like to add:**
Part of Structured Logging effort https://github.com/kubernetes/enhancements/issues/1602
/help
/priority important-soon
/sig instrumentation
/milestone v1.19

### Additional contract requirements

- `KMetadata` is an interface with methods `GetName() string` and `GetNamespace() string`.
- The public signature of `KObj` is `func KObj(obj KMetadata) ObjectRef`; the `ObjectMeta` parameter in the base declaration refers to a value implementing `KMetadata`.
- `KObj(obj KMetadata) ObjectRef` returns an `ObjectRef` whose `Name` is `obj.GetName()` and whose `Namespace` is `obj.GetNamespace()`.
- `ObjectRef` has a `String() string` method that returns `"namespace/name"` when `Namespace` is non-empty, and just `Name` otherwise.
