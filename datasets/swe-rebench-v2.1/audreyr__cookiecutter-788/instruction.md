Provide a __main__.py for the package
By providing a `__main__.py` file in the `cookiecutter` package it allows for `python.exe -m cookiecutter` to work (and the entry point can then simply point at the `__main__` module). I would be happy to provide a PR for this if you're amenable to the addition.

### Additional contract requirements

- Running the package as a module (`python -m cookiecutter`) executes the
  Cookiecutter CLI. For example, `python -m cookiecutter --version` exits with
  status 0 and prints the version string, which begins with `Cookiecutter`.
