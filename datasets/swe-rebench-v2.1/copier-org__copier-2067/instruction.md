When running `copier update`, responses to questions with "when==false" retain the last answers instead of reverting to the defaults.
### Describe the problem

Hi,

In the [documentation](https://copier.readthedocs.io/en/stable/configuring/#advanced-prompt-formatting), it states:
> - when: Condition that, if false, skips the question. ...
> If a question is skipped, its answer is not recorded, but its default value is available in the render context.

However, when `copier update` is executed, the answers to skipped questions persist as their last values instead of updating to the default values.

### Template

https://github.com/kubotty/copier-default-debug

### To Reproduce

1. Apply the template:
```bash
mkdir copier-default-check
cd copier-default-check
git init
copier copy https://github.com/kubotty/copier-default-debug.git -r 0.4.0 .
```
```
🎤 First question
Yes
🎤 Second question
Yes

Copying from template version 0.4.0
    create  file.md
    create  README.md
    create  .copier-answers.yml
```

Check the content of `file.md`:
```bash
cat file.md
```
```
- True
- True
- Yes
- Yes
```

2. Update and change the answer, but it retains the last answer:
```bash
git add .
git commit -m v0.4.0
copier update -r 0.5.0
```
```
Updating to template version 0.5.0
🎤 First question
No
```
```bash
cat file.md
```
```
- False
- True
- No
- Yes
```


### Logs

```console

```

### Expected behavior

The default values should be reflected in the updates:
```bash
copier update -r 0.5.0
    Updating to template version 0.5.0
    🎤 First question
    No
```
After checking the content of `file.md`, it should show:
```bash
cat file.md
```
Expected Output:
```
- False
- False
- No
- No
```

### Screenshots/screencasts/logs

_No response_

### Operating system

Windows

### Operating system distribution and version

Windows 11 Enterprize

### Copier version

9.6.0

### Python version

3.12

### Installation method

pipx+pypi

### Additional context

_No response_
