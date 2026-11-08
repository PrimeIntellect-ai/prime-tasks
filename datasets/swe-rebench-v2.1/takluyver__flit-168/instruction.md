Expose arbitrary project URLs
As discussed on distutils-sig, PyPI allows one to specify arbitrary URLs to show up in the sidebar of pypi.org. It would be great to expose this in flit somehow. Perhaps a `[urls]` or `[metadata.urls]` section where each key is the name of the link and the value is the URL itself, e.g.
```toml
[metadata.urls]
Documentation = "https://flit.readthedocs.io"
Development = "https://github.com/takluyver/flit"
```
Over time this could replace the `homepage` key in `[metadata]` by letting people specify that key themselves.

### Additional contract requirements

- The section that holds arbitrary project URLs is `[tool.flit.metadata.urls]` in `pyproject.toml`. Each key in that section is the link label and each value is the URL.
- A URL value that is not well-formed does not cause an error.
