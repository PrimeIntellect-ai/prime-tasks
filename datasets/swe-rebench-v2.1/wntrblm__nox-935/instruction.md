URL dependencies are sometimes silently ignored in PEP 723 noxfiles
### Current Behavior

URL dependencies in a noxfile's PEP 723 `dependencies` are silently ignored in some cases.

### Expected Behavior

Nox should not ignore any PEP 723 dependencies.

### Steps To Reproduce

Minimal reproducer:

1.  `noxfile.py`:

    ```python
    # /// script
    # requires-python = ">= 3.9"
    # dependencies = [
    #     "nox @ git+https://github.com/wntrblm/nox.git@2024.10.09",
    # ]
    # ///

    import importlib.metadata

    import nox


    @nox.session(python=False)
    def a(session: nox.Session) -> None:
        print(importlib.metadata.version("nox"))


    if __name__ == "__main__":
        import nox.__main__

        nox.__main__.main()
    ```

2.  Run `nox`

    Behavior:

    ```console
    $ nox
    nox > Running session a
    2025.2.9
    nox > Session a was successful.
    ```

    Expected behavior:

    ```console
    $ nox
    nox > Running session a
    2024.10.09
    nox > Session a was successful.
    ```

    For comparison:

    ```console
    $ pipx run noxfile.py
    nox > Running session a
    2024.10.9
    nox > Session a was successful.
    ```

    ```console
    $ uv run -s noxfile.py
    nox > Running session a
    2024.10.9
    nox > Session a was successful.
    ```

### Environment

```Markdown
- OS: Arch Linux
- Python: CPython 3.13.2
- Nox: 2025.2.9
```

### Anything else?

Whether Nox ignores a requirement depends on both the requirement and on the environment of the calling `nox`. For example, if we modify the example above:

```diff
 # dependencies = [
-#     "nox @ git+https://github.com/wntrblm/nox.git@2024.10.09",
+#     "nox[uv] @ git+https://github.com/wntrblm/nox.git@2024.10.09",
 # ]
```

then now `nox` will no longer ignore the requirement _if_ `nox` is installed a venv without uv, but `nox` will still ignore the requirement if uv is installed in the same venv as it.

Another example:

```python
# /// script
# requires-python = ">= 3.9"
# dependencies = [
#     "nox >= 2025.2.9",
#     "httpx @ git+https://github.com/encode/httpx@0.28.0",
# ]
# ///

import importlib.metadata

import nox


@nox.session(python=False)
def a(session: nox.Session) -> None:
    print(importlib.metadata.version("httpx"))


if __name__ == "__main__":
    nox.main()
```

With this one, Nox will ignore the httpx requirement if (for example) `httpx==0.28.1` is installed in the same venv as `nox`.
