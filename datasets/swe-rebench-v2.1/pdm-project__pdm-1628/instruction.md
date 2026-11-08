On Windows, `pdm run python_file.py` fails
- [X] I have searched the issue tracker and believe that this is not a duplicate.

**Make sure you run commands with `-v` flag before pasting the output.**

## Steps to reproduce

1. Create a simple test file, `test1.py`:

```python
import sys

print("Hello, world")
print(f"This is {sys.executable}")
```

2. Run the file using `pdm run test1.py`

## Actual behavior

The command fails with the following error:

```
❯ pdm run -v test1.py
Traceback (most recent call last):
  File "<frozen runpy>", line 198, in _run_module_as_main
  File "<frozen runpy>", line 88, in _run_code
  File "C:\Users\Gustav\.local\bin\pdm.exe\__main__.py", line 7, in <module>
  File "C:\Users\Gustav\.local\pipx\venvs\pdm\Lib\site-packages\pdm\core.py", line 259, in main
    return Core().main(args)
           ^^^^^^^^^^^^^^^^^
  File "C:\Users\Gustav\.local\pipx\venvs\pdm\Lib\site-packages\pdm\core.py", line 191, in main
    raise cast(Exception, err).with_traceback(traceback)
  File "C:\Users\Gustav\.local\pipx\venvs\pdm\Lib\site-packages\pdm\core.py", line 186, in main
    f(project, options)
  File "C:\Users\Gustav\.local\pipx\venvs\pdm\Lib\site-packages\pdm\cli\commands\run.py", line 393, in handle
    exit_code = runner.run(options.command, options.args)
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\Gustav\.local\pipx\venvs\pdm\Lib\site-packages\pdm\cli\commands\run.py", line 326, in run
    return self._run_process(
           ^^^^^^^^^^^^^^^^^^
  File "C:\Users\Gustav\.local\pipx\venvs\pdm\Lib\site-packages\pdm\cli\commands\run.py", line 225, in _run_process
    process = subprocess.Popen(
              ^^^^^^^^^^^^^^^^^
  File "C:\Users\Gustav\AppData\Local\Programs\Python\Python311\Lib\subprocess.py", line 1022, in __init__
    self._execute_child(args, executable, preexec_fn, close_fds,
  File "C:\Users\Gustav\AppData\Local\Programs\Python\Python311\Lib\subprocess.py", line 1491, in _execute_child
    hp, ht, pid, tid = _winapi.CreateProcess(executable, args,
                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
OSError: [WinError 193] %1 is not a valid Win32 application
```

## Expected behavior

The script should be run with the local environment active.

## Environment Information

```bash
# Paste the output of `pdm info && pdm info --env` below:
❯ pdm info; pdm info --env
PDM version:
  2.4.0
Python Interpreter:
  C:\Work\Scratch\Python\.venv\Scripts\python.exe (3.11)
Project Root:
  C:/Work/Scratch/Python
Project Packages:
  None
{
  "implementation_name": "cpython",
  "implementation_version": "3.11.0",
  "os_name": "nt",
  "platform_machine": "AMD64",
  "platform_release": "10",
  "platform_system": "Windows",
  "platform_version": "10.0.22621",
  "python_full_version": "3.11.0",
  "platform_python_implementation": "CPython",
  "python_version": "3.11",
  "sys_platform": "win32"
}
```

Note that this is on Windows, where `.py` files are not directly executable by `CreateProcess`, so the error is accurate, it's the fact that PDM is using `CreateProcess` directly to run the user's command that is the issue here.

## Workaround

It is possible to run the script using `pdm run python test1.py`. This is a viable workaround, but very error prone. Not only is it easy to forget to add `python`, but it's also easy to assume that you can use `py` instead, as that is the normal command to run Python on Windows. Unfortunately, `pdm run py test.py` will *not* run the script with the local environment, but will use the system Python (`py` uses an activated virtual environment, but `pdm run` does not activate the environment).
