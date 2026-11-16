[bug] negative numbers not parsed as integers from environment variables
**Describe the bug**
In version `1.3.9` environment variables that are negative represented as strings (e.g. `DYNACONF_NUM="-1"`) are not cast to type `int` when loaded in Python. This isn't true in  version `1.3.4`.

**To Reproduce**
Steps to reproduce the behavior:

1. Having the following folder structure

<!-- Describe or use the command `$ tree -v` and paste below -->

<details>
<summary> Project structure </summary>

```bash
.
├── test.py
└── settings.toml
```
</details>

2. Having the following config files:

<!-- Please adjust if you are using different files and formats! -->

<details>
<summary> Config files </summary>

**./settings.toml**
```toml
num = 1
```

</details>

3. Having the following app code:

<details>
<summary> Code </summary>

**./test.py**
```python
from dynaconf import Dynaconf

settings = Dynaconf(settings_file="./settings.toml")
print(settings.num)
print(type(settings.num))
```

</details>

4. Executing under the following environment

<details>
<summary> Execution </summary>

```bash
$ export DYNACONF_NUM="-1"
$ python ./test.py
```

</details>

**Expected behavior**
The python script should print the following:
```bash
-1
<class 'int'>
```

**Actual behavior**
The python script prints the following:
```bash
-1
<class 'str'>
```

**Environment (please complete the following information):**
 - OS: macOS Monerey 12.5.1
 - Dynaconf Version [e.g. 3.1.9]

**Additional context**
Again, this works as expected in version `3.1.4` so I assume something has changed in a recent version.
