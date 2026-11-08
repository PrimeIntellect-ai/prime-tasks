`validator` checks are skipped for questions with a `default` when `--defaults` option is set
### Describe the problem

When using the `--defaults` option the `validator` checks are not executed when a question sets a default and a value isn't explicitly set.

### Template

```yaml
---
title:
  type: str
  help: The human readable title
  validator: "{% if title == '' %}Title must not be empty{% endif %}"

name:
  type: str
  help: Name in kebab-case
  default: "{{ title.lower().replace(' ', '-') }}"
  validator: "{% if not (name | regex_search('^[a-z]+(-[a-z]+)*$')) %}Invalid name{% endif %}"
```

### To Reproduce

1. Create the `copier.yaml` in a directory named `template`
2. `mkdir dest`
3. `copier copy --defaults -d title=@ template foo`

### Logs

```console

```

### Expected behavior

I would expect that the `validator` logic is always run on the value of a question.

### Screenshots/screencasts/logs

_No response_

### Operating system

macOS

### Operating system distribution and version

macOS 15.4.1

### Copier version

9.6.0

### Python version

Python 3.10.13

### Installation method

distro package

### Additional context

_No response_
