RBAC generation with specific resourceNames
The regular RBAC generation annotation works great if you want to give permissions over all instances of a certain type. Say you want to give permission to get all statefulsets, that's as easy as

`// +kubebuilder:rbac:groups=apps,resources=statefulsets,verbs=get`

But what if you want to give permissions only over a few instances? For example, when dealing with PodSecurityPolicies, you'll probably want to generate an RBAC rule that looks like

```
- apiGroups:
  - policy
  resources:
  - podsecuritypolicies
  verbs:
  - use
  resourceNames:
  - psp.1
```

But there's no way to do that with the RBAC generation is there?
`// +kubebuilder:rbac:groups="policy",resources=podsecuritypolicies,verbs=use,resourceNames=psp.1`

ends up generating

```
- apiGroups:
  - policy
  resources:
  - podsecuritypolicies
  verbs:
  - use
```

So how can you generate RBAC rules for specific resource instances?
