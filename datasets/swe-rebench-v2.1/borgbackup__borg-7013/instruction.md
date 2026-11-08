archive name placeholder replacement does not work
master branch:

```
borg create arch-{now:%Y-%m-%d-%H:%M:%S%z} data --timestamp=2022-12-31-23:59:59.123456+09:30
```

results in:
```
arch-2022-08-12-21:21:31+0200
```

[HIDDEN]

### Additional contract requirements

Placeholders in archive names must be expanded, including formatted expressions such as the one shown above. When `--timestamp` is supplied, `{now}` in the archive name must reflect that timestamp rather than the current time.
