Add a `recordable_only` argument to options dictionary items method.
### Desired capability or behavior.

In some situations users may need to iterate through options to be serialized, but the presence of non-recordable options causes errors.

This could be handled by

```
for key, meta in options_dict.items():
    if meta['recordable']:
        do_something_with_this_option(key, meta)
```

This is an easy oversight and we could make the user's life somewhat easier by returning only recordable options if requested:

```
for key, meta in options_dict.items(recordable_only=True):
    do_something_with_this_option(key, meta)
```




### Associated POEM

None
