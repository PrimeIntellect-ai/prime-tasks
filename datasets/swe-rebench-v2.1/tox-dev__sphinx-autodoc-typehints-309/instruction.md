Unexpected output when class attribute and constructor arg have same name (napoleon bug)
This is an upstream bug: https://github.com/sphinx-doc/sphinx/pull/11143

Suppose we have the following class:
```py
class Example:
    """
    A Class

    Parameters
    ----------
    blah:
        Description of parameter blah
    """
    def __init__(self, blah: CodeType):
        pass

    blah: ModuleType
```

We get the following output (just the parameters):
```
   Parameters:
      **blah** (*module*) -- Description of parameter blah
```
Expected output:
```
   Parameters:
      **blah** ("CodeType") -- Description of parameter blah
```
If you want I can provide a monkey patch that implements my fix in https://github.com/sphinx-doc/sphinx/pull/11143 on existing versions of sphinx. I'm not sure how far we want to go in patching with upstream bugs.
