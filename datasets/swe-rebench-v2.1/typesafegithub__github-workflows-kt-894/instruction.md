[Core feature request] runsOn should accept a list
**What feature do you need?**

from https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#jobsjob_idruns-on:

> If you specify an array of strings, your workflow will execute on any runner that matches all of the specified runs-on values.

**Do you have an example usage?**

```yaml
jobs:
  build:
    runs-on: [self-hosted, X64]
```

**Is there a workaround for not having this feature? If yes, please describe it.**

no

### Additional contract requirements

The library exposes `RunnerType.Labelled(vararg labels: String)` to configure an ordered set of runner labels. When a job uses this runner type, its `runs-on` YAML value is an array containing the supplied labels, in order.
