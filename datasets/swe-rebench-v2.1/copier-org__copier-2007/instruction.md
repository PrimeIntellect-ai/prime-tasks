UnicodeDecodeError when updating on Windows
### Describe the problem

During the update of a project to a new template version I got an UnicodeDecodeError.
The update was therefore incomplete.


### Template

Template: https://github.com/dalito/linkml-project-copier
Repo that was updated (from v0.2.2 to v0.3.0): https://github.com/nfdi4cat/pid4cat-model

### To Reproduce

_No response_

### Logs

```console
λ copier update --trust --skip-answered
Updating to template version 0.3.0
Traceback (most recent call last):
  File "<frozen runpy>", line 198, in _run_module_as_main
  File "<frozen runpy>", line 88, in _run_code
  File "C:\Users\david\.local\bin\copier.exe\__main__.py", line 7, in <module>
  File "C:\Users\david\.local\pipx\venvs\copier\Lib\site-packages\plumbum\cli\application.py", line 640, in run
    inst, retcode = subapp.run(argv, exit=False)
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\david\.local\pipx\venvs\copier\Lib\site-packages\plumbum\cli\application.py", line 635, in run
    retcode = inst.main(*tailargs)
              ^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\david\.local\pipx\venvs\copier\Lib\site-packages\copier\cli.py", line 425, in main
    return _handle_exceptions(inner)
           ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\david\.local\pipx\venvs\copier\Lib\site-packages\copier\cli.py", line 70, in _handle_exceptions
    method()
  File "C:\Users\david\.local\pipx\venvs\copier\Lib\site-packages\copier\cli.py", line 415, in inner
    with self._worker(
         ^^^^^^^^^^^^^
  File "C:\Users\david\.local\pipx\venvs\copier\Lib\site-packages\copier\main.py", line 254, in __exit__
    raise value
  File "C:\Users\david\.local\pipx\venvs\copier\Lib\site-packages\copier\cli.py", line 423, in inner
    worker.run_update()
  File "C:\Users\david\.local\pipx\venvs\copier\Lib\site-packages\copier\main.py", line 1031, in run_update
    self._apply_update()
  File "C:\Users\david\.local\pipx\venvs\copier\Lib\site-packages\copier\main.py", line 1239, in _apply_update
    if any(
       ^^^^
  File "C:\Users\david\.local\pipx\venvs\copier\Lib\site-packages\copier\main.py", line 1242, in <genexpr>
    for line in conflicts_candidate
                ^^^^^^^^^^^^^^^^^^^
  File "C:\dev\Python312\Lib\encodings\cp1252.py", line 23, in decode
    return codecs.charmap_decode(input,self.errors,decoding_table)[0]
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
UnicodeDecodeError: 'charmap' codec can't decode byte 0x90 in position 712: character maps to <undefined>
```

### Expected behavior

The update should run to completion.

### Screenshots/screencasts/logs

_No response_

### Operating system

macOS

### Operating system distribution and version

Windows 10 Pro, German locale

### Copier version

copier 9.5.0

### Python version

CPython 3.12

### Installation method

pipx+pypi

### Additional context

_No response_
