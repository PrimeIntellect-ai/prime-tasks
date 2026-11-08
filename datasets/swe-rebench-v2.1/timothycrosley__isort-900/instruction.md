'user' is not a Python3 package
In Python2 'user' was a package, but not anymore in Python3.

Seems you are using it as a python package:
https://github.com/timothycrosley/isort/blob/develop/isort/settings.py#L99

It is somehow related to: https://github.com/PyCQA/pylint/issues/2532

Thank you.
