pip-compile broken with pip 19.0
Describe the issue briefly here.

##### Environment Versions

1. OS Type
darwin
1. Python version: `$ python -V`
Python 2.7.15
1. pip version:  `$ pip --version`
pip 19.0 from /Users/brandon/src/images/.venv/lib/python2.7/site-packages/pip (python 2.7)
1. pip-tools version: `$ pip-compile --version`
pip-compile, version 3.2.0

##### Steps to replicate

```sh
$ pip-compile --generate-hashes --upgrade --header --index --annotate --output-file $@ $<
Traceback (most recent call last):
  File "/Users/brandon/src/images/.venv/bin/pip-compile", line 10, in <module>
    sys.exit(cli())
  File "/Users/brandon/src/images/.venv/lib/python2.7/site-packages/click/core.py", line 764, in __call__
    return self.main(*args, **kwargs)
  File "/Users/brandon/src/images/.venv/lib/python2.7/site-packages/click/core.py", line 717, in main
    rv = self.invoke(ctx)
  File "/Users/brandon/src/images/.venv/lib/python2.7/site-packages/click/core.py", line 956, in invoke
    return ctx.invoke(self.callback, **ctx.params)
  File "/Users/brandon/src/images/.venv/lib/python2.7/site-packages/click/core.py", line 555, in invoke
    return callback(*args, **kwargs)
  File "/Users/brandon/src/images/.venv/lib/python2.7/site-packages/piptools/scripts/compile.py", line 130, in cli
    repository = PyPIRepository(pip_options, session)
  File "/Users/brandon/src/images/.venv/lib/python2.7/site-packages/piptools/repositories/pypi.py", line 62, in __init__
    process_dependency_links=pip_options.process_dependency_links,
AttributeError: Values instance has no attribute 'process_dependency_links'
