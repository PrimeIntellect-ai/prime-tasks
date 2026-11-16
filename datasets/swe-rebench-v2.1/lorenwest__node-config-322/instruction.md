TypeError: Property description must be an object: undefined
With the latest version, 1.20.2, I get the following error when trying to use the util.extendDeep() function:

```
.../node_modules/config/lib/config.js:1420
        Object.defineProperty(mergeInto, prop, [HIDDEN]);
               ^
TypeError: Property description must be an object: undefined
    at Function.defineProperty (native)
    at .../node_modules/config/lib/config.js:1420:16
    at Array.forEach (native)
    at util.extendDeep (.../node_modules/config/lib/config.js:1400:9)
```

This occurs when extending one config with another config on the 'get' function.
[HIDDEN]

### Additional contract requirements

- `util.extendDeep()` must not throw the reported TypeError when extending one configuration with another on its `get` function.
