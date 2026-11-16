Future Python versions might be problematic with the definition of Environment Marker Variable `python_version`
There might be a problem with https://github.com/pypa/packaging/blob/c22fbd8c7bfa989df911243b10901645b7d4758d/packaging/markers.py#L267 in the future.

The line is using the definition of the Environment Marker Variable `python_version` according to PEP 508. But what if the Python version will consist of more than 3 characters?

I originally posted this as a question on Stack Overflow https://stackoverflow.com/questions/48119291/whats-with-the-definition-of-environment-marker-variable-python-version-in-pe Just as Martijn Pieters wrote there, something like `[HIDDEN]` would fix the problem.

I guess, the PEP would have to be changed first?

### Additional contract requirements

- The `python_version` environment marker must represent the Python major and minor version components, preserving all digits of each component, including multi-digit components.
