pypy-3.10 doesn't work as an interpreter name
### Current Behavior

GitHub Actions called PyPy interpreters `pypy-3.10`. I think we call them `pypy3.10`. Should we support the GHA form too?

### Additional contract requirements

- When a `VirtualEnv` is constructed with `interpreter="pypy-3.10"`, its `interpreter` attribute must be `pypy3.10`.
