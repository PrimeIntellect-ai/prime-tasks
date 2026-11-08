Rule version specifier should allow for multiple versions
If the rule is only valid for set of versions, ie rule was introduced in RF 5 but will not make sense after RF 8:

```
version=">=5;<8"
```

We can use ";" in version specifier to separate different versions. Rule will be only enabled if it matches all conditions from the list.
