Issue with ArgoCD Connaisseur change tag in deployment resource to digest
**Describe the bug**
Connaisseur version 3.5.0 and 3.4.0 have issue with mutation of deployment objects which cause argocd to stay out-of-sync.

I want to disable mutation of some kubernetes objects like deployments,statefulset and deamonset.
Tried following:
1) Set mode in policy definition (with.mode) to insecureValidateOnly. Nothing happend argocd still modified deployment objects.
2) Tried with resource validation mode (https://sse-secure-systems.github.io/connaisseur/v3.5.0/features/resource_validation_mode/) set resourceValidationMode to "podsOnly", got following error in argocd

one or more objects failed to apply, reason: Internal error occurred: failed calling webhook "connaisseur-svc.connaisseur.svc": received invalid webhook response: webhook returned response.patchType but not response.patch

**Expected behavior**
Dont want connaisseur to mutate deployment objects just pods.

**Optional: Versions (please complete the following information as relevant):**
 - Kubernetes Cluster: 1.28.9
 - Container registry: jfrog
 - Connaisseur: 3.5.0
