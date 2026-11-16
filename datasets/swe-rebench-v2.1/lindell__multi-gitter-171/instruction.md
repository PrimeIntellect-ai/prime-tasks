Gitlab: Does not support nested groups
**Describe the bug**
When using the `project` attribute in the yaml config or on the command line it does not support sub-groups on GitLab.

When running a config that has:

```yaml
project:
  - group-org/subgroup/project
```

It fails with the following message:

`could not parse repository reference: group-org/subgroup/project`

[HIDDEN]

Changing the second slash to URI encoded slash (`group-org/subgroup%2Fproject`) allows me to pass the validation function but then it errors when actually trying to fetch the repository.

**Expected behavior**
I'd expect it to allow projects in nested groups on Gitlab.

Hope this is clear enough! Nice tool BTW! 👍🏾

### Additional contract requirements

- GitLab project references with nested groups must be accepted from both YAML configuration and the command line, and must allow the intended project to be fetched using its complete namespace and project path.
