AttributeError: 'History' object has no attribute 'id'
Hi,

I think one of the latest taiga-back commits broke python-taiga if not entirely but quite badly.
I see they made changes to the history management in taiga-back (they fixed something with timeline history loops on fresh projects) and I suppose it had some effect on this tool.

This gets raised when I'm trying to get a project by its slug:
`AttributeError: 'History' object has no attribute 'id'`

Got no idea where to fix it yet.

### Additional contract requirements

- Fetching a project by slug must not fail with an `AttributeError` when a `History` object has no `id` attribute.
- Converting a `History` object to a string with `str()` or `repr()` must not fail when it has no `id` attribute, and the result must include the class name `History`.
