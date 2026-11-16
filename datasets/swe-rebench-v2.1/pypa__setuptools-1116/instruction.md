pkg_resources.find_on_path() thinks the zc.recipe.egg wheel is an egg
Originally reported by: **mgedmin (Bitbucket: [mgedmin](http://bitbucket.org/mgedmin), GitHub: [mgedmin](http://github.com/mgedmin))**

---

Steps to reproduce: try to `pip install zc.recipe.egg`.  You'll get an error:

```
zc.recipe.egg is in an unsupported or invalid wheel
```

If you hack pip's sources to expose the real traceback, you'll see [this](https://github.com/pypa/pip/issues/3028#issuecomment-148614984):

```
Traceback (most recent call last):
  File "/home/qwcode/p/pypa/pip/pip/basecommand.py", line 200, in main
    status = self.run(options, args)
  File "/home/qwcode/p/pypa/pip/pip/commands/install.py", line 302, in run
    root=options.root_path,
  File "/home/qwcode/p/pypa/pip/pip/req/req_set.py", line 657, in install
    **kwargs
  File "/home/qwcode/p/pypa/pip/pip/req/req_install.py", line 805, in install
    version = pip.wheel.wheel_version(self.source_dir)
  File "/home/qwcode/p/pypa/pip/pip/wheel.py", line 559, in wheel_version
    wheel_data = dist.get_metadata('WHEEL')
  File "/home/qwcode/p/pypa/pip/pip/_vendor/pkg_resources/__init__.py", line 1611, in get_metadata
    return self._get(self._fn(self.egg_info, name))
  File "/home/qwcode/p/pypa/pip/pip/_vendor/pkg_resources/__init__.py", line 1722, in _get
    with open(path, 'rb') as stream:
IOError: [Errno 2] No such file or directory: '/tmp/pip-build-ucnzjI/zc.recipe.egg/EGG-INFO/WHEEL'
```

AFAIU the problem is the following check in pkg_resources.find_on_path():

``` python
    if os.path.isdir(path_item) and os.access(path_item, os.R_OK):
        [HIDDEN]
```

This is wrong: the unpacked zc.recipe.egg _wheel_ has a top-level directory called `zc.recipe.egg`.

See https://github.com/pypa/pip/issues/3028 for more background.

---
- Bitbucket: https://bitbucket.org/pypa/setuptools/issue/462

### Additional contract requirements

- Distribution discovery must not report an unpacked project directory as an egg solely because its name ends in `.egg`; in particular, this applies to the `zc.recipe.egg` wheel directory.
- Genuine installed unpacked and zipped egg distributions in a target directory must remain discoverable.
- When discovery is limited to the target directory with `only=True`, it must not descend into egg directories beneath that target.
