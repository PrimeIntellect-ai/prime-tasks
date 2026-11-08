[bug] Regression: get_history() of dynamic value throwing DynaconfFormatError
**Describe the bug**
In release 3.2.6 calling `get_history()` on a `LazySettings` object with a dotted key having a dynamic `@format` value incorrectly throws a `dynaconf.utils.parse_conf.DynaconfFormatError`. This is a regression from release 3.2.5. A minimal reproducable example is provided below.

**To Reproduce**
Steps to reproduce the behavior:

1. Having the following folder structure

<!-- Describe or use the command `$ tree -v` and paste below -->

<details>
<summary> Project structure </summary>

```bash
.
├── get_history_bug.py
└── settings.toml

1 directory, 2 files
```
</details>

2. Having the following config files:

<!-- Please adjust if you are using different files and formats! -->

<details>
<summary> Config files </summary>

**settings.toml**
```toml
[default]

[a]
b = "foo"
c = "bar"
d = "@format {this.a.b} {this.a.c}"
```

</details>

3. Having the following app code:

<details>
<summary> Code </summary>

**get_history_bug.py**
```python
from dynaconf import Dynaconf, get_history
from pprint import pprint

settings = Dynaconf(settings_files=["settings.toml"])

def main() -> None:
    pprint(settings.as_dict())
    print(f"Expecting to get the history of key 'a.d' with value {settings['a']['d']}")
    pprint(get_history(settings, "a.d"))

if __name__ == "__main__":
    main()
```

</details>

4. Executing under the following environment

<details>
<summary> Execution </summary>

```bash
% python3 -m venv .venv
% source .venv/bin/activate
% pip3 install dynaconf==3.2.6
Collecting dynaconf==3.2.6
  Obtaining dependency information for dynaconf==3.2.6 from https://files.pythonhosted.org/packages/e2/14/c8a7d861262139688fa465d2e27ff7113764d6fa03b15b9c7b666729ea2e/dynaconf-3.2.6-py2.py3-none-any.whl.metadata
  Using cached dynaconf-3.2.6-py2.py3-none-any.whl.metadata (9.1 kB)
Using cached dynaconf-3.2.6-py2.py3-none-any.whl (231 kB)
Installing collected packages: dynaconf
Successfully installed dynaconf-3.2.6

[notice] A new release of pip is available: 23.2.1 -> 24.2
[notice] To update, run: pip install --upgrade pip
% python3 get_history_bug.py
{'A': {'b': 'foo', 'c': 'bar', 'd': 'foo bar'}, 'DEFAULT': {}}
Expecting to get the history of key 'a.d' with value foo bar
Traceback (most recent call last):
  File "/home/glenn.mcallister/dynaconf-mre/.venv/lib64/python3.12/site-packages/dynaconf/utils/parse_conf.py", line 151, in __call__
    return self.function(value, **context)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
AttributeError: 'dict' object has no attribute 'a'

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/home/glenn.mcallister/dynaconf-mre/get_history_bug.py", line 12, in <module>
    main()
  File "/home/glenn.mcallister/dynaconf-mre/get_history_bug.py", line 9, in main
    pprint(get_history(settings, "a.d"))
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/glenn.mcallister/dynaconf-mre/.venv/lib64/python3.12/site-packages/dynaconf/utils/inspect.py", line 264, in get_history
    data = _get_data_by_key(data, key, sep=sep) if key else data
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/glenn.mcallister/dynaconf-mre/.venv/lib64/python3.12/site-packages/dynaconf/utils/inspect.py", line 335, in _get_data_by_key
    return traverse_data(data, key_dotted_path)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/glenn.mcallister/dynaconf-mre/.venv/lib64/python3.12/site-packages/dynaconf/utils/inspect.py", line 331, in traverse_data
    result = result[key]
             ~~~~~~^^^^^
  File "/home/glenn.mcallister/dynaconf-mre/.venv/lib64/python3.12/site-packages/dynaconf/utils/boxing.py", line 26, in evaluate
    return recursively_evaluate_lazy_format(value, settings)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/glenn.mcallister/dynaconf-mre/.venv/lib64/python3.12/site-packages/dynaconf/utils/__init__.py", line 424, in recursively_evaluate_lazy_format
    return _recursively_evaluate_lazy_format(value, settings)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/glenn.mcallister/dynaconf-mre/.venv/lib64/python3.12/site-packages/dynaconf/utils/__init__.py", line 432, in _recursively_evaluate_lazy_format
    value = value(settings)
            ^^^^^^^^^^^^^^^
  File "/home/glenn.mcallister/dynaconf-mre/.venv/lib64/python3.12/site-packages/dynaconf/utils/parse_conf.py", line 234, in __call__
    result = self.formatter(self.value, **self.context)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/glenn.mcallister/dynaconf-mre/.venv/lib64/python3.12/site-packages/dynaconf/utils/parse_conf.py", line 155, in __call__
    raise DynaconfFormatError(
dynaconf.utils.parse_conf.DynaconfFormatError: Dynaconf can't interpolate variable because 'dict' object has no attribute 'a'
```

</details>

**Expected behavior**
As in releases 3.2.4 and 3.2.5 I expected to get the history for the key, as demonstrated below with 3.2.5:

<details>
<summary> Execution </summary>

```bash
% python3 -m venv .venv
% source .venv/bin/activate
% pip3 install dynaconf==3.2.5
Collecting dynaconf==3.2.5
  Obtaining dependency information for dynaconf==3.2.5 from https://files.pythonhosted.org/packages/d6/b1/9b995a140fa4984047b44653036b655ed52680a2293a481614539bc01a07/dynaconf-3.2.5-py2.py3-none-any.whl.metadata
  Using cached dynaconf-3.2.5-py2.py3-none-any.whl.metadata (9.1 kB)
Using cached dynaconf-3.2.5-py2.py3-none-any.whl (230 kB)
Installing collected packages: dynaconf
Successfully installed dynaconf-3.2.5

[notice] A new release of pip is available: 23.2.1 -> 24.2
[notice] To update, run: pip install --upgrade pip
% python3 get_history_bug.py
{'A': {'b': 'foo', 'c': 'bar', 'd': 'foo bar'}, 'DEFAULT': {}}
Expecting to get the history of key 'a.d' with value foo bar
[{'env': 'default',
  'identifier': '/home/glenn.mcallister/dynaconf-mre/settings.toml',
  'loader': 'toml',
  'merged': False,
  'value': '@format {this.a.b} {this.a.c}'}]
```

</details>

**Environment (please complete the following information):**
 - OS: Linux/Fedora39
 - Dynaconf Version: 3.2.6
 - Frameworks in use: None

**Additional context**
- N/A
