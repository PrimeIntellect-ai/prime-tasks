Breaking long line does not preserve links
Hi, first, for this nice tool!
We crossed some difficulty with long links which are split into multiple lines (when a line is over 120 chars) but then it is not valid link anymore, for example this one:
```
`Area Under the Receiver Operating Characteristic Curve (ROC AUC)
    <https://en.wikipedia.org/wiki/Receiver_operating_characteristic#Further_interpretations>`_.
```
is there some solution for such a case? for example, do when the link is too long start automatically on a new line and even the line is too long, do not break it...

### Additional contract requirements

- When formatting the following docstrings with description wrapping set to 72, produce exactly the shown output.

Input:
```
"""This is a docstring with a link.

    Here is an elaborate description containing a link.
    `Area Under the Receiver Operating Characteristic Curve (ROC AUC)
        <https://en.wikipedia.org/wiki/Receiver_operating_characteristic#Further_interpretations>`_.
    """
```
Output:
```
"""This is a docstring with a link.

    Here is an elaborate description containing a link. `Area Under the
    Receiver Operating Characteristic Curve (ROC AUC)
    <https://en.wikipedia.org/wiki/Receiver_operating_characteristic#Further_interpretations>`_.
    """
```

Input:
```
"""This is another docstring with a link.

    See http://www.reliqual.com/wiki/how_to_use_ramstk/verification_and_validation_module/index.html for additional information.
    """
```
Output:
```
"""This is another docstring with a link.

    See
    http://www.reliqual.com/wiki/how_to_use_ramstk/verification_and_validation_module/index.html
    for additional information.
    """
```

Input:
```
"""This is another docstring with `a link`_.

    .. a link: http://www.reliqual.com/wiki/how_to_use_ramstk/
    verification_and_validation_module/index.html.
    """
```
Output:
```
"""This is another docstring with `a link`_.

    .. a link: http://www.reliqual.com/wiki/how_to_use_ramstk/verification_and_validation_module/index.html.
    """
```
