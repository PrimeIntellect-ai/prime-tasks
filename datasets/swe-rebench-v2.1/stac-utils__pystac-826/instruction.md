Asset: clone() doesn't clone extra_fields
If you do asset.clone() you get a shallow copy, but as extra_field is explicitily a member of the class, I'd expect that it at least also get cloned.

The following code adds `abc` to both asset and mask, which is somewhat unexpected:
```py
fields = {}
asset = Asset(
    href=href,
    extra_fields=fields,
)
mask = asset.clone()
mask.extra_fields["abc"] = True
```
