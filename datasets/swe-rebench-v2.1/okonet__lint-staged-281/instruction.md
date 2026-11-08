Better error handling If config is missing
Right now, if `lint-staged` is run on a project with no config file, this happens:

```
Could not parse lint-staged config.
Make sure you have created it. See https://github.com/okonet/lint-staged#readme.

TypeError: Cannot read property 'config' of null
```

Would be great if lint-staged could say for sure:

```
Config could not be found.

Please make sure you have created it. See https://github.com/okonet/lint-staged#configuration.
```
