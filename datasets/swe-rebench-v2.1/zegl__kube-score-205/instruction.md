Feature: disable annotation kube-score/ignore with option
**Which version of kube-score are you using?**

> kube-score version: 1.4.0

**What did you do?**

I want to cancel deployment on Kubernetes if my clients don't respect checks requirements with kubescore.

**What did you expect to see?**

But with annotation kube-score/ignore, my clients are able to deactivate some checks that are required for deployment.

**What did you see instead?**

It would be great if an option was able to disable annotation kube-score/ignore when we do checks analytics with kubescore before deployment.

### Additional contract requirements

Provide the `--disable-ignore-checks-annotations` command-line option to prevent `kube-score/ignore` annotations from suppressing their associated checks. When this option is not selected, preserve the existing behavior in which those annotations can suppress checks.
