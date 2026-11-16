SecurityContext settings for executor container not fully honoured
Checklist:

 * [ ] I've included the version.
 * [ ] I've included reproduction steps.
 * [ ] I've included the workflow YAML.
 * [ ] I've included the logs.

**What happened**:

Nothing

**What you expected to happen**:

The configured security context to be applied to the wait pod.

**How to reproduce it (as minimally and precisely as possible)**:

Configure the workflow-controller as:

```
executor:
  securityContext:
    runAsUser: 1000
```

Start any workflow, inspect the wait container (with, say, `kubelet get pod ... -o yaml`).

---
<!-- Issue Author: Don't delete this message to ecourage other users to support your issue! -->
**Message from the maintainers**:

If you are impacted by this bug please add a 👍 reaction to this issue! We often sort issues this way to know what to prioritize.
