[BUG] DID NOT WARN errors on two tests
### setuptools version

main

### Python version

3.13.2

### OS

macOS

### Additional environment information

_No response_

### Description

Today I tried running the Setuptools tests and I'm getting two errors, seemingly due to warnings emitted as errors:

```
py: commands[0]> pytest -p no:cov --lf
=============================================================== test session starts ===============================================================
platform darwin -- Python 3.13.2, pytest-8.3.5, pluggy-1.5.0
cachedir: .tox/py/.pytest_cache
rootdir: /Users/jaraco/code/pypa/setuptools
configfile: pytest.ini
plugins: enabler-3.3.0, mypy-0.10.3, checkdocs-2.13.0, jaraco.vcs-2.4.1, jaraco.test-5.5.1, home-0.6.0, ruff-0.4.1, subprocess-1.5.3, perf-0.15.0, timeout-2.3.1, xdist-3.6.1
12 workers [2 items]
FF                                                                                                                                          [100%]
==================================================================== FAILURES =====================================================================
_____________________________________________________ TestMetadata.test_warn_dash_deprecation _____________________________________________________
[gw0] darwin -- Python 3.13.2 /Users/jaraco/code/pypa/setuptools/.tox/py/bin/python

self = <setuptools.tests.config.test_setupcfg.TestMetadata object at 0x103369130>
tmpdir = local('/private/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pytest-of-jaraco/pytest-16/popen-gw0/test_warn_dash_deprecation0')

    def test_warn_dash_deprecation(self, tmpdir):
        # warn_dash_deprecation() is a method in setuptools.dist
        # remove this test and the method when no longer needed
        fake_env(
            tmpdir,
            '[metadata]\n'
            'author-email = test@test.com\n'
            'maintainer_email = foo@foo.com\n',
        )
        msg = "Usage of dash-separated 'author-email' will not be supported"
        with pytest.warns(SetuptoolsDeprecationWarning, match=msg):
>           with get_dist(tmpdir) as dist:

setuptools/tests/config/test_setupcfg.py:434:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
/opt/homebrew/Cellar/python@3.13/3.13.2/Frameworks/Python.framework/Versions/3.13/lib/python3.13/contextlib.py:141: in __enter__
    return next(self.gen)
setuptools/tests/config/test_setupcfg.py:68: in get_dist
    parse and dist.parse_config_files()
.tox/py/lib/python3.13/site-packages/_virtualenv.py:22: in parse_config_files
    result = old_parse_config_files(self, *args, **kwargs)
setuptools/dist.py:646: in parse_config_files
    self._parse_config_files(filenames=inifiles)
setuptools/dist.py:493: in _parse_config_files
    opt = self.warn_dash_deprecation(opt, section)
setuptools/dist.py:541: in warn_dash_deprecation
    SetuptoolsDeprecationWarning.emit(
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

cls = <class 'setuptools.warnings.SetuptoolsDeprecationWarning'>, summary = 'Invalid dash-separated options'
details = "\n                Usage of dash-separated 'author-email' will not be supported in future\n                versions. Please use the underscore name 'author_email' instead.\n                "
due_date = (2025, 3, 3), see_docs = 'userguide/declarative_config.html', see_url = None, stacklevel = 2, kwargs = {}
summary_ = 'Invalid dash-separated options'
details_ = "\n                Usage of dash-separated 'author-email' will not be supported in future\n                versions. Please use the underscore name 'author_email' instead.\n                "
docs_ref = 'userguide/declarative_config.html', docs_url = 'https://setuptools.pypa.io/en/latest/userguide/declarative_config.html'
due = datetime.date(2025, 3, 3)
text = 'Invalid dash-separated options\n!!\n\n        ***********************************************************************...nfig.html for details.\n        ********************************************************************************\n\n!!'

    @classmethod
    def emit(
        cls,
        summary: str | None = None,
        details: str | None = None,
        due_date: _DueDate | None = None,
        see_docs: str | None = None,
        see_url: str | None = None,
        stacklevel: int = 2,
        **kwargs,
    ) -> None:
        """Private: reserved for ``setuptools`` internal use only"""
        # Default values:
        summary_ = summary or getattr(cls, "_SUMMARY", None) or ""
        details_ = details or getattr(cls, "_DETAILS", None) or ""
        due_date = due_date or getattr(cls, "_DUE_DATE", None)
        docs_ref = see_docs or getattr(cls, "_SEE_DOCS", None)
        docs_url = docs_ref and f"https://setuptools.pypa.io/en/latest/{docs_ref}"
        see_url = see_url or getattr(cls, "_SEE_URL", None)
        due = date(*due_date) if due_date else None

        text = cls._format(summary_, details_, due, see_url or docs_url, kwargs)
        if due and due < date.today() and _should_enforce():
>           raise cls(text)
E           setuptools.warnings.SetuptoolsDeprecationWarning: Invalid dash-separated options
E           !!
E
E                   ********************************************************************************
E                   Usage of dash-separated 'author-email' will not be supported in future
E                   versions. Please use the underscore name 'author_email' instead.
E
E                   This deprecation is overdue, please update your project and remove deprecated
E                   calls to avoid build errors in the future.
E
E                   See https://setuptools.pypa.io/en/latest/userguide/declarative_config.html for details.
E                   ********************************************************************************
E
E           !!

setuptools/warnings.py:51: SetuptoolsDeprecationWarning

During handling of the above exception, another exception occurred:

self = <setuptools.tests.config.test_setupcfg.TestMetadata object at 0x103369130>
tmpdir = local('/private/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pytest-of-jaraco/pytest-16/popen-gw0/test_warn_dash_deprecation0')

    def test_warn_dash_deprecation(self, tmpdir):
        # warn_dash_deprecation() is a method in setuptools.dist
        # remove this test and the method when no longer needed
        fake_env(
            tmpdir,
            '[metadata]\n'
            'author-email = test@test.com\n'
            'maintainer_email = foo@foo.com\n',
        )
        msg = "Usage of dash-separated 'author-email' will not be supported"
>       with pytest.warns(SetuptoolsDeprecationWarning, match=msg):
E       Failed: DID NOT WARN. No warnings of type (<class 'setuptools.warnings.SetuptoolsDeprecationWarning'>,) were emitted.
E        Emitted warnings: [].

setuptools/tests/config/test_setupcfg.py:433: Failed
_____________________________________________________ TestMetadata.test_make_option_lowercase _____________________________________________________
[gw1] darwin -- Python 3.13.2 /Users/jaraco/code/pypa/setuptools/.tox/py/bin/python

self = <setuptools.tests.config.test_setupcfg.TestMetadata object at 0x105359250>
tmpdir = local('/private/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pytest-of-jaraco/pytest-16/popen-gw1/test_make_option_lowercase0')

    def test_make_option_lowercase(self, tmpdir):
        # remove this test and the method make_option_lowercase() in setuptools.dist
        # when no longer needed
        fake_env(tmpdir, '[metadata]\nName = foo\ndescription = Some description\n')
        msg = "Usage of uppercase key 'Name' in 'metadata' will not be supported"
        with pytest.warns(SetuptoolsDeprecationWarning, match=msg):
>           with get_dist(tmpdir) as dist:

setuptools/tests/config/test_setupcfg.py:446:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
/opt/homebrew/Cellar/python@3.13/3.13.2/Frameworks/Python.framework/Versions/3.13/lib/python3.13/contextlib.py:141: in __enter__
    return next(self.gen)
setuptools/tests/config/test_setupcfg.py:68: in get_dist
    parse and dist.parse_config_files()
.tox/py/lib/python3.13/site-packages/_virtualenv.py:22: in parse_config_files
    result = old_parse_config_files(self, *args, **kwargs)
setuptools/dist.py:646: in parse_config_files
    self._parse_config_files(filenames=inifiles)
setuptools/dist.py:494: in _parse_config_files
    opt = self.make_option_lowercase(opt, section)
setuptools/dist.py:566: in make_option_lowercase
    SetuptoolsDeprecationWarning.emit(
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

cls = <class 'setuptools.warnings.SetuptoolsDeprecationWarning'>, summary = 'Invalid uppercase configuration'
details = "\n            Usage of uppercase key 'Name' in 'metadata' will not be supported in\n            future versions. Please use lowercase 'name' instead.\n            "
due_date = (2025, 3, 3), see_docs = 'userguide/declarative_config.html', see_url = None, stacklevel = 2, kwargs = {}
summary_ = 'Invalid uppercase configuration'
details_ = "\n            Usage of uppercase key 'Name' in 'metadata' will not be supported in\n            future versions. Please use lowercase 'name' instead.\n            "
docs_ref = 'userguide/declarative_config.html', docs_url = 'https://setuptools.pypa.io/en/latest/userguide/declarative_config.html'
due = datetime.date(2025, 3, 3)
text = 'Invalid uppercase configuration\n!!\n\n        **********************************************************************...nfig.html for details.\n        ********************************************************************************\n\n!!'

    @classmethod
    def emit(
        cls,
        summary: str | None = None,
        details: str | None = None,
        due_date: _DueDate | None = None,
        see_docs: str | None = None,
        see_url: str | None = None,
        stacklevel: int = 2,
        **kwargs,
    ) -> None:
        """Private: reserved for ``setuptools`` internal use only"""
        # Default values:
        summary_ = summary or getattr(cls, "_SUMMARY", None) or ""
        details_ = details or getattr(cls, "_DETAILS", None) or ""
        due_date = due_date or getattr(cls, "_DUE_DATE", None)
        docs_ref = see_docs or getattr(cls, "_SEE_DOCS", None)
        docs_url = docs_ref and f"https://setuptools.pypa.io/en/latest/{docs_ref}"
        see_url = see_url or getattr(cls, "_SEE_URL", None)
        due = date(*due_date) if due_date else None

        text = cls._format(summary_, details_, due, see_url or docs_url, kwargs)
        if due and due < date.today() and _should_enforce():
>           raise cls(text)
E           setuptools.warnings.SetuptoolsDeprecationWarning: Invalid uppercase configuration
E           !!
E
E                   ********************************************************************************
E                   Usage of uppercase key 'Name' in 'metadata' will not be supported in
E                   future versions. Please use lowercase 'name' instead.
E
E                   This deprecation is overdue, please update your project and remove deprecated
E                   calls to avoid build errors in the future.
E
E                   See https://setuptools.pypa.io/en/latest/userguide/declarative_config.html for details.
E                   ********************************************************************************
E
E           !!

setuptools/warnings.py:51: SetuptoolsDeprecationWarning

During handling of the above exception, another exception occurred:

self = <setuptools.tests.config.test_setupcfg.TestMetadata object at 0x105359250>
tmpdir = local('/private/var/folders/f2/2plv6q2n7l932m2x004jlw340000gn/T/pytest-of-jaraco/pytest-16/popen-gw1/test_make_option_lowercase0')

    def test_make_option_lowercase(self, tmpdir):
        # remove this test and the method make_option_lowercase() in setuptools.dist
        # when no longer needed
        fake_env(tmpdir, '[metadata]\nName = foo\ndescription = Some description\n')
        msg = "Usage of uppercase key 'Name' in 'metadata' will not be supported"
>       with pytest.warns(SetuptoolsDeprecationWarning, match=msg):
E       Failed: DID NOT WARN. No warnings of type (<class 'setuptools.warnings.SetuptoolsDeprecationWarning'>,) were emitted.
E        Emitted warnings: [].

setuptools/tests/config/test_setupcfg.py:445: Failed
============================================================= short test summary info =============================================================
FAILED setuptools/tests/config/test_setupcfg.py::TestMetadata::test_warn_dash_deprecation - Failed: DID NOT WARN. No warnings of type (<class 'setuptools.warnings.SetuptoolsDeprecationWarning'>,) were emitted.
FAILED setuptools/tests/config/test_setupcfg.py::TestMetadata::test_make_option_lowercase - Failed: DID NOT WARN. No warnings of type (<class 'setuptools.warnings.SetuptoolsDeprecationWarning'>,) were emitted.
================================================================ 2 failed in 2.52s ================================================================
py: exit 1 (2.75 seconds) /Users/jaraco/code/pypa/setuptools> pytest -p no:cov --lf pid=54523
  py: FAIL code 1 (6.05=setup[3.30]+cmd[2.75] seconds)
  evaluation failed :( (6.11 seconds)
```

These failures are happening on 8e39bc907, which passed CI, so there's something about my environment that's triggering the failures.

### Expected behavior

Tests should pass

### How to Reproduce

tox

### Output

```console

```

### Additional contract requirements

When parsing setup.cfg metadata, the legacy option `author-email` must cause a hard configuration error rather than being accepted with only a deprecation warning. The legacy option `Name` must likewise cause a hard configuration error.
