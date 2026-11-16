--data-file option fails with UTF-8 YAML file on systems with non-UTF-8 default encoding
### Describe the problem

On systems with non-UTF-8 default encodings (like CP932 on Japanese Windows), using the `--data-file` option with UTF-8 encoded YAML files results in encoding errors.

This happens because the current implementation opens files in text mode without specifying an encoding:

```python
def data_file_switch(self, path: cli.ExistingFile) -> None:
    """Update [data][] with provided values.

    Arguments:
        path: The path to the YAML file to load.
    """
    with Path(path).open() as f:
        file_updates: AnyByStrDict = yaml.safe_load(f)
```

When the system's default encoding is not UTF-8, UTF-8 encoded YAML files cannot be read correctly.

To avoid this issue, users must save their YAML file using the system's default encoding rather than the Unicode encoding that is expected for YAML files.

#### Proposed Solution

[HIDDEN]
[HIDDEN]

### Template

not a template problem

### To Reproduce

On Japanese Windows 10 (in my case)
1. Create a data file `myparams.yml` and save it in UTF-8.
2. Run `copier copy --data-file .\myparams.yml .\template .\output`

### Logs

```console
Traceback (most recent call last):
  File "M:\Dev\copier\venv\Scripts\\copier", line 6, in <module>
    sys.exit(copier_app_run())
             ^^^^^^^^^^^^^^^^
  File "M:\Dev\copier\venv\Lib\site-packages\plumbum\cli\application.py", line 640, in run
    inst, retcode = subapp.run(argv, exit=False)
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "M:\Dev\copier\venv\Lib\site-packages\plumbum\cli\application.py", line 631, in run
    f(inst, *a)
  File "M:\Dev\copier\copier-master\copier\cli.py", line 193, in data_file_switch
    file_updates: AnyByStrDict = yaml.safe_load(f)
                                 ^^^^^^^^^^^^^^^^^
  File "M:\Dev\copier\venv\Lib\site-packages\yaml\__init__.py", line 125, in safe_load
    return load(stream, SafeLoader)
           ^^^^^^^^^^^^^^^^^^^^^^^^
  File "M:\Dev\copier\venv\Lib\site-packages\yaml\__init__.py", line 79, in load
    loader = Loader(stream)
             ^^^^^^^^^^^^^^
  File "M:\Dev\copier\venv\Lib\site-packages\yaml\loader.py", line 34, in __init__
    Reader.__init__(self, stream)
  File "M:\Dev\copier\venv\Lib\site-packages\yaml\reader.py", line 85, in __init__
    self.determine_encoding()
  File "M:\Dev\copier\venv\Lib\site-packages\yaml\reader.py", line 124, in determine_encoding
    self.update_raw()
  File "M:\Dev\copier\venv\Lib\site-packages\yaml\reader.py", line 178, in update_raw
    data = self.stream.read(size)
           ^^^^^^^^^^^^^^^^^^^^^^
UnicodeDecodeError: 'cp932' codec can't decode byte 0x86 in position 6: illegal multibyte sequence
```

### Expected behavior

`--data-file` option reads UTF-8 YAML file correctly.

### Screenshots/screencasts/logs

_No response_

### Operating system

Windows

### Operating system distribution and version

Japanese Windows 10

### Copier version

0.0.0

### Python version

CPython 3.11

### Installation method

local build

### Additional context

_No response_

### Additional contract requirements

- When `--data-file` is used, UTF-8 YAML (including UTF-8 with a BOM), UTF-16LE YAML, and UTF-16BE YAML must be read correctly regardless of the system's default text encoding, and the loaded values must be available to the copy operation.
