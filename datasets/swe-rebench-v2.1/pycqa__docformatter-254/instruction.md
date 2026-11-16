Wrapping yield tag
Hi,
With the latest docformatter (1.7.4) any yield tags in my docstrings are being wrapped into the line above.
```
    """
    My test fixture.

    :param caplog: Pytest caplog fixture.
    :yield: Until test complete, then run cleanup.
    """
```
Turns into
```
    """
    My test fixture.

    :param caplog: Pytest caplog fixture. :yield: Until test complete, then run cleanup.
    """
```

I understand that `yield` is not part of the official Sphinx docstring spec, but we have adopted them as we use darglint to lint our docstrings and that flags a `DAR301 Missing "Yields" in Docstring" if we do not document our yield.
Plus it is good to be able to document what functions yield within their docstring.

I am running docformatter in a pre-commit hook with the following configuration:
```
  - repo: https://github.com/pycqa/docformatter
    rev: v1.7.4
    hooks:
      - id: docformatter
        args:
          - --black
          - --in-place
          - --pre-summary-newline
          - --wrap-summaries=120
          - --wrap-descriptions=120
```
