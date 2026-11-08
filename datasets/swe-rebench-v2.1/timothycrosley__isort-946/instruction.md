Update isort to follow pyi (stub files) standards, in similar fashion to black
Currently, isort is unaware of the differences between the established coding standards for `.py` files and `.pyi` files, treating them the same. This ticket represents updating isort to be aware of these differences, in particular for `.pyi` files and follow the appropriate standard for the given file type. https://github.com/python/typeshed/blob/master/CONTRIBUTING.md#stub-file-coding-style provides a good initial intro to the `.pyi` specific standards.

In particular, any resolution to this ticket should resolve the incompatibility with Black outlined here: https://github.com/python/black/issues/837
