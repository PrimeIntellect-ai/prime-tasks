Handling of find_links in setup.cfg in 42.0.0
Hi,

I have a couple of `setup_requires` dependencies in my setup.py and my setup.cfg looks like this:

```
[easy_install]
find_links = https://example.com
```

Looking at: https://github.com/pypa/setuptools/blob/e84f616a6507ec9115fad68b221cbf5333d9d2d9/setuptools/installer.py#L119

The `cmd` ends up being:

```python
['python', '-m', 'pip', '--disable-pip-version-check', 'wheel', '--no-deps', '-w', '/tmp/tmpWyNzjZ', '--quiet', '--find-links', 'h', '--find-links', 't', '--find-links', 't', '--find-links', 'p', '--find-links', 's', '--find-links', ':', '--find-links', '/', '--find-links', '/', '--find-links', 'e', '--find-links', 'x', '--find-links', 'a', '--find-links', 'm', '--find-links', 'p', '--find-links', 'l', '--find-links', 'e', '--find-links', '.', '--find-links', 'c', '--find-links', 'o', '--find-links', 'm', 'babel; extra == "i18n"']
```
It seems the assumption was that `find_links` is a list but it ends up being a string.

Additionally, since pip is unable to build/fetch a wheel, the following line throws an IndexError:
https://github.com/pypa/setuptools/blob/e84f616a6507ec9115fad68b221cbf5333d9d2d9/setuptools/installer.py#L122

Perhaps this could be caught and a more user-friendly error displayed instead.

### Additional contract requirements

When fetching a `setup_requires` dependency fails, report the failure as a `DistutilsError` rather than leaking an `IndexError`.
