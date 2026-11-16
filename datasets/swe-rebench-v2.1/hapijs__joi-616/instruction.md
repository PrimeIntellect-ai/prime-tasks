Error when .rename() from undefined
Hi,
here's what I'm trying to do :
I've got this Joi schema
```js
var validateQuery = core.Joi.object().keys({
  clientId: core.Joi.string().required(),
  redirectUri: core.Joi.string().required().regex(/^[a-z0-9]*:\/\/[^*]*/i),
  responseType: core.Joi.string().required().valid(['code', 'token']),
}).rename('client_id', 'clientId', {override: true})
  .rename('redirect_uri', 'redirectUri', {override: true})
  .rename('response_type', 'responseType', {override: true});
```
and I'm validating this object
```js
  redirectUri: 'http://whatever.com',
  responseType: 'token',
  clientId: '240f17d59129425093d9ec805009e75e' }
```
This give me ` [ValidationError: child "clientId" fails because ["clientId" is required]]`. Changing clientId to client_id in my object works fine, but rename() shouldn't delete my keys if the rename isn't necessary, right? I think this behavior is comming from [this commit](https://github.com/hapijs/joi/commit/c46617de6f33bb5c4a32cf9949e8d815abfef798#diff-5e2f31e54109ac080317d872767c943dR107) but maybe it's on purpose and I missed something.

Is that a bug or a feature ?

### Additional contract requirements

- The `ignoreUndefined: true` option to `.rename()` is opt-in. When enabled, if the source key is absent or its value is `undefined`, the rename is skipped and any existing destination key is preserved.
