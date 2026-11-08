pyproject.toml should be included in sdist by default
An issue came up at work recently where installing [python-daemon](https://pagure.io/python-daemon) with `pip` was hitting the `easy_install` path. I assumed it was because `python-daemon` didn't have a `pyproject.toml`, but it turns out they do - it's just not included in the `Manifest.in`, so it didn't get included in the `sdist`. To verify this I created a super basic example project and it does seem that the default is to exclude `pyproject.toml`.

Given that `pyproject.toml` is one of the most important files to have when executing a build, it should be included in the sdist unless explicitly excluded.
