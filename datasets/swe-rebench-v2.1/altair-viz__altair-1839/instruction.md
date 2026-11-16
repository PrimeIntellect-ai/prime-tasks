Internal: overzealous dataset conversion
Example:
```
>>> alt.LookupData.from_dict({'data': {'values': []}, 'key': 'x'}).to_dict()
{'data': {'name': 'data-d751713988987e9331980363e24189ce'}, 'key': 'x'}
```
The issue is it assumes that ``context`` is always relevant; we should properly handle ``context=None``.
