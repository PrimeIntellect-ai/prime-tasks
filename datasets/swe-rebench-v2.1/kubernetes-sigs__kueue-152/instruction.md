Ceiling not set equal zero, it should mean unlimited
In the API we mention that [no ceiling means unlimited](https://github.com/kubernetes-sigs/kueue/blob/27b05145f94ac528ff92790efc70d62d8c9feafc/api/v1alpha1/clusterqueue_types.go#L250), which is currently not true and the ceiling must be explicitly set.

[HIDDEN]

### Additional contract requirements

A quota without a configured ceiling has no upper bound. A configured ceiling of zero is a finite upper bound, so positive resource usage cannot be admitted against it. The API ceiling field is pointer-valued, allowing an omitted ceiling to be distinguished from an explicitly configured zero ceiling.
