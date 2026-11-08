Image references mutated even when mode is set to insecureValidateOnly
**Describe the bug**
<A clear and concise description of what the bug is.>
Image references in the pod definition is mutated and the digests are included even when `with.mode` is set to **insecureValidateOnly** in the policies.

Below is the extract from `connaisseur-app-config` configmap.
```
data:
  config.yaml: |
    validators:
    -
      name: default
      trustRoots:
      - key: |
          <KEY>
        name: default
      type: cosign
    policy:
    -
      pattern: '*:*'
      validator: default
      with:
        mode: insecureValidateOnly
        verifyInTransparencyLog: false
```

Logs in the Connaisseur pod
```
{
  "level": "info",
  "msg": "successfully validated image sfbrdevhelmweacr.azurecr.io/stakater/reloader:v1.0.95 using rule *:* and validator default. Result is sfbrdevhelmweacr.azurecr.io/stakater/reloader:v1.0.95@sha256:5e15985882a8312abe5281aaae61301089244d5a33470eba16a7aeca715340c9.",
  "time": "2024-11-10T15:28:24Z"
}
```

**Expected behavior**
<A clear and concise description of what you expected to happen.>
Only the validation should happen and the image references should not be mutated.

**Optional: To reproduce**
<Stepwise guide or instructions or minimal example to reproduce.>
Deployment with the above config should reproduce the issue

**Optional: Versions (please complete the following information as relevant):**
 - OS: Redhat8.6
 - Kubernetes Cluster: RKE2 (1.30.5)
 - Container registry: Azure Container Registry
 - Connaisseur: v3.7.0


**Optional: Additional context**
<Add any other context or screenshots about the bug here.>
This causes applications as OutOfSync in Argocd. Is any additional configuration needed to do only validation?
