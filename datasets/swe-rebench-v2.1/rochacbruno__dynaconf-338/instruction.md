Inconsistent/undefined behavior in when accessing settings with lower-case names
Hey, I'd like to discuss this behavior I just encountered when I was using a Dynaconf Settings object alongside a regular dict, and trying to use the same code for accessing both of them.  Assuming there is a Dynaconf Settings instance named `settings` that has the parameter `PORT` set to 8080, the following behavior can be observed when accessing the parameter:

1. Using key ("bracket") notation:

    ```python
    >>> settings["PORT"]
    8080

    >>> settings["port"]
    8080
    ```

1. Using .get:

    ```python
    >>> settings.get("PORT")
    8080

    >>> settings.get("port")
    8080
    ```

1. Using attribute ("dot") notation:

    ```python
    >>> settings.PORT
    8080

    >>> settings.port
    …
    AttributeError: 'Settings' object has no attribute 'port'
    ```

The outlier here is obviously the lower-case dot notation, right? But here is where the behavior actually differs from a dictionary:

```python
>>> "PORT" in settings
True

>>> "port" in settings
False
```

Taking into account _all_ returned results above, the last statement should _also_ respond `True`, because it contradicts the "dict-like" ways to access it (`.get` and key notation) where the lower-case variable is indeed "in settings".

As far as I can see the documentation does not mention this, which is why I'd like to propose defining a consistent behavior regarding upper/lower-casing parameters in Dynaconf. IMHO the behavior should be consistent across all access patterns, and I think Dynaconf should internally be case-insensitive and support both lower-case and upper-case parameter access. The casing should only matter on environment variables (always to be upper-case) where lower-case variables don't generally work.

What do you think?

### Additional contract requirements

Lower-case reads are enabled by passing `LOWERCASE_READ_FOR_DYNACONF=True` to `LazySettings`. When they are enabled, setting names must be accessible consistently in either case through bracket, `get`, attribute, and membership access. Environment-variable names remain case-sensitive; a lower-case spelling must not be treated as equivalent to an upper-case environment-variable name.
