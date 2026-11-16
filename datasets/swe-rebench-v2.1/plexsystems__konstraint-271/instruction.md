Merge duplicate matcher annotations
I want duplicate instances of `@kinds` and `@matchLabels` annotations to merge into resulting matchers instead of overriding last one – so they match behaviour of `@matchExpression`, `@namespaces` and `@excludedNamespaces`

For example, I want these annotations:
```rego
# @kinds apps/Deployment apps/ReplicaSet apps/StatefulSet apps/DaemonSet
# @kinds core/Pod
# @matchlabels foo=bar
# @matchlabels env=prod
```

to produce following spec.match:
```yaml
kinds:
- apiGroups:
  - ""
  kinds:
  - Pod
- apiGroups:
  - apps
  kinds:
  - Deployment
  - ReplicaSet
  - StatefulSet
  - DaemonSet
labelSelector:
  matchLabels:
    env: prod
    foo: bar
```

instead of this:
```yaml
kinds:
- apiGroups:
  - ""
  kinds:
  - Pod
labelSelector:
  matchLabels:
    env: prod
```
