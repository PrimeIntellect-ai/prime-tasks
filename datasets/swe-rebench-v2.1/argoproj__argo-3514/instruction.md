Backoff exponent is off by one
Checklist:

 * [x] I've included the version.
 * [x] I've included reproduction steps.
 * [x] I've included the workflow YAML.
 * [ ] I've included the logs.

**What happened**:
Given the retry strategy below, the first retry attempt backs off 10 minutes.
```
     retryStrategy:
       limit: 2
       retryPolicy:
       backoff: "Always"
         duration: "5m"
         factor: 2
```

**What you expected to happen**:
The first retry attempt should backoff 5 minutes and the second one backoff 10 minutes.

As far as I know, most retry libraries use the duration as the initial duration. For example, the backoff package used by apiserver ([ref](https://github.com/argoproj/argo/blob/master/server/apiserver/argoserver.go#L116)) is implemented this way ([ref](https://github.com/kubernetes/apimachinery/blob/master/pkg/util/wait/wait.go#L215)).

**How to reproduce it (as minimally and precisely as possible)**:
1. Delete the pod while the workflow is running.
1. The backoff message is displayed in the UI: `Retrying in 9 minutes 59 seconds`.

**Anything else we need to know?**:

**Environment**:

- Argo version: v2.7.5 (but it should reproduce in master too)

---
<!-- Issue Author: Don't delete this message to encourage other users to support your issue! -->
**Message from the maintainers**:

If you are impacted by this bug please add a 👍 reaction to this issue! We often sort issues this way to know what to prioritize.
