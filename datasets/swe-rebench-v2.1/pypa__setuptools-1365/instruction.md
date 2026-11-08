package_dir and setup.cfg version attr: <foo> mutually exclusive?
I was messing around with the new ``setup.cfg`` support for metadata, and it looks like there is a poor interaction with ``package_dir`` and the version field support, specifically if you have a ``setup.cfg`` like:

```
[metadata]
version = attr: foobar.__version__

[options]
package_dir =
    = src
```

You'll get an error trying to import foobar. This is because it simply appends the current directory to ``sys.path`` and then attempts to import the above.
