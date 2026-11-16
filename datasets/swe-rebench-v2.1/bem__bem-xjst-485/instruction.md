Wrap should save BEMContext
After [commit](https://github.com/bem/bem-xjst/commit/578c89a204cf79ad54f2ef360e03792e8f95cebf) `wrap()` have a degradation.

https://goo.gl/tTb2yZ

cc @tadatuta

### Additional contract requirements

- Wrapped content must be processed in the active BEMContext, so an element without an explicit block resolves relative to the current block. This applies whether the wrapped content is supplied directly or returned by a function.
