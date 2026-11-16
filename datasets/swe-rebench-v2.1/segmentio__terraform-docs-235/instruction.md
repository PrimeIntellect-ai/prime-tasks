Error: open main.tf: no such file or directory (use with pre-commit)
Hi!

### Prerequisites

- [x] This issue describes a bug.

### Description

Since version 0.9.0, terraform-docs seems to require a `main.tf`. In my company standards, some of our projects does not have a `maint.tf`…

#### Actual Behavior

When a project does
```
$ pre-commit run -a

Error: open main.tf: no such file or directory
```

#### Expected Behavior

Not sure the problem come from terraform-docs because it still runs as is, however only terraform-docs has changed. Within pre-commit: v0.8.2 works, v0.9.0 does not.
Maybe you could give me useful information.

### Version

erraform-docs version v0.9.0 89b129b linux/amd64 BuildDate: 2020-03-31T20:19:01+0000

### Additional contract requirements

A project must not fail solely because it lacks `main.tf`.
