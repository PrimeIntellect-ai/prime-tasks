[HIDDEN] proxyExcludedKeys
As discussed [here](https://github.com/domenic/chai-as-promised/issues/220#issuecomment-328989791) it would be great if the [HIDDEN] [`proxyExcludedKeys`](https://github.com/chaijs/chai/blob/0d19b3518265ba0ff17689a3ae1dc7e7b6c6bf16/lib/chai/config.js#L93):
in `lib/chai/config.js`.
Thanks go to @meeber

### Additional contract requirements

- The default value of `proxyExcludedKeys` must be `['then', 'catch', 'inspect', 'toJSON']`.
