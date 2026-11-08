Add version number to library
So that we can run `axelrod.__version__` or something like that.

This should be trivial, nice to not duplicate what is in `setup.py` obviously.

### Additional contract requirements

- The library version must be readable as `axelrod.__version__`, and its value must be a string.
- Running `python setup.py --version` from the repository root must print the same version string as `axelrod.__version__`, so the number does not have to be maintained in two separate places.
