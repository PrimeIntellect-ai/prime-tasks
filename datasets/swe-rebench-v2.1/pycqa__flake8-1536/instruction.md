physical line plugins aren't passed every physical line when an expression contains a multiline string
### how did you install flake8?

```console
$ pip install git+https://github.com/pycqa/flake8@ca573a7ccf2d4a1c7df0b577bb6d3455c941e828
Collecting git+https://github.com/pycqa/flake8@ca573a7ccf2d4a1c7df0b577bb6d3455c941e828
  Cloning https://github.com/pycqa/flake8 (to revision ca573a7ccf2d4a1c7df0b577bb6d3455c941e828) to /tmp/pip-req-build-lh3_65yl
  Running command git clone --filter=blob:none -q https://github.com/pycqa/flake8 /tmp/pip-req-build-lh3_65yl
  Running command git rev-parse -q --verify 'sha^ca573a7ccf2d4a1c7df0b577bb6d3455c941e828'
  Running command git fetch -q https://github.com/pycqa/flake8 ca573a7ccf2d4a1c7df0b577bb6d3455c941e828
  Resolved https://github.com/pycqa/flake8 to commit ca573a7ccf2d4a1c7df0b577bb6d3455c941e828
  Preparing metadata (setup.py) ... done
Requirement already satisfied: mccabe<0.7.0,>=0.6.0 in ./venv/lib/python3.8/site-packages (from flake8==4.0.1) (0.6.1)
Requirement already satisfied: pycodestyle<2.9.0,>=2.8.0 in ./venv/lib/python3.8/site-packages (from flake8==4.0.1) (2.8.0)
Requirement already satisfied: pyflakes<2.5.0,>=2.4.0 in ./venv/lib/python3.8/site-packages (from flake8==4.0.1) (2.4.0)
Building wheels for collected packages: flake8
  Building wheel for flake8 (setup.py) ... done
  Created wheel for flake8: filename=flake8-4.0.1-py2.py3-none-any.whl size=61251 sha256=96363641001fa7562bbd594af37564c697971950775dcd9335e7d7f94cad3238
  Stored in directory: /home/asottile/.cache/pip/wheels/9b/f3/37/5b6c870430baba34a27d437055cfdb1b431514495819e6fd0b
Successfully built flake8
Installing collected packages: flake8
  Attempting uninstall: flake8
    Found existing installation: flake8 4.0.1
    Uninstalling flake8-4.0.1:
      Successfully uninstalled flake8-4.0.1
Successfully installed flake8-4.0.1
```


### unmodified output of `flake8 --bug-report`

```json
{
  "platform": {
    "python_implementation": "CPython",
    "python_version": "3.8.10",
    "system": "Linux"
  },
  "plugins": [
    {
      "plugin": "mccabe",
      "version": "0.6.1"
    },
    {
      "plugin": "pycodestyle",
      "version": "2.8.0"
    },
    {
      "plugin": "pyflakes",
      "version": "2.4.0"
    }
  ],
  "version": "4.0.1"
}
```


### describe the problem

#### what I expected to happen

I expect to get two physical lines outputted such as:

```console
$ flake8 t.py
'no_flake8_e501_error = "My line longer than 80 chars xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" + """\n'
'"""\n'
```


#### sample code

(t.py)
```python
no_flake8_e501_error = "My line longer than 80 chars xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" + """
"""
```

(plug.py)
```python
def plug(physical_line: str):
    print(repr(physical_line))
    return
    yield
```

(setup.cfg)
```ini
[flake8:local-plugins]
extension =
    A=plug:plug
paths = .
```

#### commands ran

```console
$ flake8 t.py
'"""\n'
'"""\n'
```
