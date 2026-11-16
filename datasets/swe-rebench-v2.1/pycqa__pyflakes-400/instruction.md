Detect type hint comments: PEP484

*Original report by [w-thomas-q](https://launchpad.net/~w-thomas-q) on [Launchpad](https://bugs.launchpad.net/bugs/1587170):*

------------------------------------

Hi,

thanks for this really great tool!
One issues I stumbled upon was that type hints seem to be ignored / not detected.
For example, we have an import at the top of a file:

    from typing import List

And then later in an `__init__` function something like this:

    self.scripts = []  # type: List[script.Script]


Now running pyflakes (through flake8) gives me this error:

    foo.py:4:1: F401 'List' imported but unused


PEP484 defines this kind of type comments.
Is there an option to enable type hint detection?
Or can we have that as feature request? I guess I'm fine with type comments only for the time being, but of course a fully PEP484 compliant solution would be greatly appreciated :)

Thanks!

### Additional contract requirements

When an imported name is referenced only in a valid PEP 484 type comment, Pyflakes must treat that name as used and must not report it as an unused import.
