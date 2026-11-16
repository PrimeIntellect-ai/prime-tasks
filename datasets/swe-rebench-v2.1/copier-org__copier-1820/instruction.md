`preserve_symlinks=False` not working for directory symlinks in 9.4
### Describe the problem

When using a template containing symlinked directories (like [here](https://github.com/DiamondLightSource/python-copier-template/blob/2.3.0/template/.vscode)) then in 9.3.1 it would follow the link, and render the contents of the directory. In 9.4 it errors with:
```python
Traceback (most recent call last):
  File "/venv/bin/copier", line 8, in <module>
    sys.exit(copier_app_run())
             ^^^^^^^^^^^^^^^^
  File "/venv/lib/python3.11/site-packages/plumbum/cli/application.py", line 640, in run
    inst, retcode = subapp.run(argv, exit=False)
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/venv/lib/python3.11/site-packages/plumbum/cli/application.py", line 635, in run
    retcode = inst.main(*tailargs)
              ^^^^^^^^^^^^^^^^^^^^
  File "/venv/lib/python3.11/site-packages/copier/cli.py", line 281, in main
    return _handle_exceptions(inner)
           ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/venv/lib/python3.11/site-packages/copier/cli.py", line 70, in _handle_exceptions
    method()
  File "/venv/lib/python3.11/site-packages/copier/cli.py", line 272, in inner
    with self._worker(
  File "/venv/lib/python3.11/site-packages/copier/main.py", line 237, in __exit__
    raise value
  File "/venv/lib/python3.11/site-packages/copier/cli.py", line 279, in inner
    worker.run_copy()
  File "/venv/lib/python3.11/site-packages/copier/main.py", line 841, in run_copy
    self._render_template()
  File "/venv/lib/python3.11/site-packages/copier/main.py", line 618, in _render_template
    self._render_file(src_relpath, dst_relpath)
  File "/venv/lib/python3.11/site-packages/copier/main.py", line 647, in _render_file
    new_content = src_abspath.read_bytes()
                  ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/pathlib.py", line 1050, in read_bytes
    with self.open(mode='rb') as f:
         ^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/pathlib.py", line 1044, in open
    return io.open(self, mode, buffering, encoding, errors, newline)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
IsADirectoryError: [Errno 21] Is a directory: '/tmp/copier.vcs.clone.akuro384/template/.vscode'
```

### Template

https://github.com/DiamondLightSource/python-copier-template/blob/2.3.0

### To Reproduce

1. `wget https://raw.githubusercontent.com/DiamondLightSource/python-copier-template/refs/tags/2.3.0/example-answers.yml`
2. `copier copy --vcs-ref=2.3.0 --trust --data-file example-answers.yml gh:DiamondLightSource/python-copier-template /tmp/foo`
3. See the traceback

### Logs

_No response_

### Expected behavior

Expected to render the contents like with 9.3.1

### Screenshots/screencasts/logs

_No response_

### Operating system

Linux

### Operating system distribution and version

python:3.11 container

### Copier version

9.4.0

### Python version

CPython 3.11

### Installation method

pip+pypi

### Additional context

The relevant code in 9.3.1: https://github.com/copier-org/copier/blob/53f1901822e795a033659bd1ac28949fa49e2003/copier/main.py#L691-L697

Which works as:
```Python 3.11.10 (main, Sep 27 2024, 06:09:18) [GCC 12.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> from pathlib import Path
>>> p = Path("./template/.vscode")
>>> p.is_dir()
True
>>> p.is_symlink()
True
>>>
```

While the code in 9.4: https://github.com/copier-org/copier/blob/59f13c079864b0cdc7aabc1bca3babb2f95f9ba0/copier/main.py#L613-L618

Which doesn't work as:
```
>>> xs = list(os.scandir("./template"))
>>> xs
[<DirEntry '.devcontainer'>, <DirEntry '.gitignore'>, <DirEntry '.pre-commit-config.yaml'>, <DirEntry '.vscode'>, <DirEntry 'Dockerfile.jinja'>, <DirEntry 'LICENSE'>, <DirEntry 'README.md.jinja'>, <DirEntry 'pyproject.toml.jinja'>, <DirEntry 'src'>, <DirEntry 'tests'>, <DirEntry '{% if git_platform=="github.com" %}.github{% endif %}'>, <DirEntry '{% if sphinx %}docs{% endif %}'>, <DirEntry '{{ _copier_conf.answers_file }}.jinja'>, <DirEntry '{% if github_org == "DiamondLightSource" %}catalog-info.yaml{% endif %}.jinja'>]
>>> xs[3]
<DirEntry '.vscode'>
>>> xs[3].is_dir()
True
>>> xs[3].is_dir(follow_symlinks=False)
False
```

[HIDDEN]

### Additional contract requirements

- When `preserve_symlinks=False`, directory symlinks in a template are followed, and their contents are rendered at the corresponding destination paths.
