bug: `copier update` throws error if previously selected value is  disabled
### Describe the problem

When trying to update the project created from template, we ran into the scenario where previously selected value choice was disabled, causing an error.

We have a setup similar to this:
```
version:
  type: str
  help: Choose your Python version
  choices:
    - "3.8"
    - "3.9"

image:
  type: str
  help: Choose a base Docker image
  choices:
    slim (python==3.8):
      value: slim-3.8
      validator: '{% if version == "3.8" %}{% else %}does not apply{% endif %}'
    bullseye (python==3.8):
      value: bullseye-3.8
      validator: '{% if version == "3.8" %}{% else %}does not apply{% endif %}'
    alpine (python==3.9):
      value: alpine-3.9
      validator: '{% if version == "3.9" %}{% else %}does not apply{% endif %}'
    bullseye (python==3.9):
      value: bullseye-3.9
      validator: '{% if version == "3.9" %}{% else %}does not apply{% endif %}'
```

Basic idea is to show different docker images based on previous versions, and there might be scenario where some images only available only certain versions.

What would be best way to overcome this error? Is this a bug on `copier` side?

### Template

Minimal examples to reproduce the issue:
- template: https://github.com/MantasPetrikasVinted/copier-playground
- filled project: https://github.com/MantasPetrikasVinted/copier-playground-filled

### To Reproduce

1. Run `copier copy git@github.com:MantasPetrikasVinted/copier-playground.git`
2. Select `3.8` and `slim-3.8`
3. Run `copier update`
4. Select `3.9`
5. Get error message

or

1. Run `git clone git@github.com:MantasPetrikasVinted/copier-playground-filled`
2. Run `copier update`
3. Select `3.9`
4. Get error message




### Logs

```console
copier-playground-filled git:(main) copier update
No git tags found in template; using HEAD as ref
Updating to template version 0.0.0.post3.dev0+1b21cd9
No git tags found in template; using HEAD as ref
🎤 Choose your Python version
   3.9
Traceback (most recent call last):
  File "/Users/mantas/.local/bin/copier", line 8, in <module>
    sys.exit(copier_app_run())
             ^^^^^^^^^^^^^^^^
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/plumbum/cli/application.py", line 638, in run
    inst, retcode = subapp.run(argv, exit=False)
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/plumbum/cli/application.py", line 633, in run
    retcode = inst.main(*tailargs)
              ^^^^^^^^^^^^^^^^^^^^
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/decorator.py", line 232, in fun
    return caller(func, *(extras + args), **kw)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/cli.py", line 71, in handle_exceptions
    return method(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/cli.py", line 402, in main
    with self._worker(
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/main.py", line 205, in __exit__
    raise value
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/cli.py", line 410, in main
    worker.run_update()
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/main.py", line 826, in run_update
    self._apply_update()
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/main.py", line 882, in _apply_update
    with replace(
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/main.py", line 205, in __exit__
    raise value
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/main.py", line 890, in _apply_update
    current_worker.run_copy()
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/main.py", line 745, in run_copy
    self._ask()
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/copier/main.py", line 454, in _ask
    new_answer = unsafe_prompt(
                 ^^^^^^^^^^^^^^
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/questionary/prompt.py", line 221, in unsafe_prompt
    question = create_question_func(**_kwargs)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/questionary/prompts/select.py", line 146, in select
    ic = InquirerControl(
         ^^^^^^^^^^^^^^^^
  File "/Users/mantas/.local/pipx/venvs/copier/lib/python3.12/site-packages/questionary/prompts/common.py", line 274, in __init__
    raise ValueError(
ValueError: Invalid 'initial_choice' value ('<questionary.prompts.common.Choice object at 0x108887410>'). It must be a selectable value.
```


### Expected behavior

First selectable value is selected


### Operating system distribution and version

macOS Ventura 13.6

### Copier version

copier 9.1.1

### Python version

Python 3.9.17

### Installation method

pipx+pypi
