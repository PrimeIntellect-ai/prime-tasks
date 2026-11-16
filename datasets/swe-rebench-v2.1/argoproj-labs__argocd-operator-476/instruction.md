reconcile resource inclusions from Argo CD CR
**Describe the bug**
Operator currently ignores changes to resource inclusions expressed in the argo-cd CR instead of reconciling them in the config map

**To Reproduce**
Steps to reproduce the behavior:
1. Deploy operator
2. Update the argo-cd CR resource inclusions
3. wait for config map to be reconciled
4. config map does not reflect changes in resource inclusions

**Expected behavior**
changes made to argo-cd CR concerning resource inclusions should be reflected in the `argocd-cm` config map

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Additional context**
Original issue: https://issues.redhat.com/browse/GITOPS-1518
Slack thread : https://coreos.slack.com/archives/CMP95ST2N/p1635956090105300
