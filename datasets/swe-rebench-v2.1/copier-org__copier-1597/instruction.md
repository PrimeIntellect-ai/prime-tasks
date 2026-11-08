default option for choices with multiselect
### Describe the problem

When enabling multiselect, the default value is not selected

### Template

```yaml
python_version:
  type: str
  help: What version of python are you targeting?
  default: "3.11"
  choices:
    - "3.8"
    - "3.9"
    - "3.10"
    - "3.11"
    - "3.12"

github_runner_python_version:
  type: str
  help: Which Python versions do you want to use on your Github Runner?
  default: "{{ python_version }}"
  multiselect: true
  choices:
    - "3.8"
    - "3.9"
    - "3.10"
    - "3.11"
    - "3.12"
 ```

### To Reproduce

Use the supplied template and copy, see that the version is not selected

### Logs

_No response_

### Expected behavior

`github_runner_python_version` already has the `python_version` selected

### Screenshots/screencasts/logs

_No response_

### Operating system

Linux

### Operating system distribution and version

Debian bookworm

### Copier version

copier 9.2.0

### Python version

Python 3.11.8

### Installation method

pip+pypi

### Additional context

_No response_

### Additional contract requirements

For a `multiselect` question, the `default` is a list of choices. Each element of
that list is a Jinja template that must be rendered before it is matched against the
question's choices. In the example above, `default: ["{{ python_version }}"]` renders
to `["3.11"]`, so `3.11` is pre-selected in the multiselect prompt and the resulting
answer for `github_runner_python_version` is `["3.11"]`.
