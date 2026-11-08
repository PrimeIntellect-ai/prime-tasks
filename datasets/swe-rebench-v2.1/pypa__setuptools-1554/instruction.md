build_meta does not include setup.py
When someone invokes the build operation via the ``build_meta`` (via https://github.com/pypa/setuptools/blob/master/setuptools/build_meta.py#L170 - https://www.python.org/dev/peps/pep-0517/#build-sdist) the ``setup.py`` is no longer automatically packaged.

In case of ``python setup.py sdist`` what ensured that this will happen is https://github.com/python/cpython/blob/master/Lib/distutils/command/sdist.py#L250. [HIDDEN]

Note the files to package is determined while running ``egg_info``, and this is re-used across runs (by reading ``SOURCES.txt``). Therefore this bug is hidden when:
- anyone beforehand calls ``python setup.py sdist``,
- when there's a distutils extension that automatically pulls in setup.py (such as setuptools-scm),
- when some config value pulls in (one in ``MANIFEST.in``, ``setup.cfg``, ``setup.py``).

### Additional contract requirements

A fresh source distribution built through ``build_meta`` must include an existing ``setup.py`` by default, without depending on a previous source-distribution build or other configuration to add it. An explicit ``MANIFEST.in`` exclusion of ``setup.py`` must continue to exclude it.
