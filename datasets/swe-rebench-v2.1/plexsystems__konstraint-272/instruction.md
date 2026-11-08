Unexpected match.kinds generated when matching multiple apiGroups
I expect `@kinds` matchers to produce `spec.match.kinds` combined by apiGroups, instead of producing single `kinds` matcher for all apiGroups and all kinds.

For example, I expect this annotation:
```rego
# @kinds core/Pod apps/Deployment
```

To produce following `spec.match.kinds`:
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
```

instead of currently generated:
```yaml
- apiGroups:
  - ""
  - apps
  kinds:
  - Pod
  - Deployment
```
