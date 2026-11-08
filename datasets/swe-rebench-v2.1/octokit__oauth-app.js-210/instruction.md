OAuthApp.defaults()
**What’s missing?**

Compare https://github.com/octokit/core.js#defaults

```js
const MyOAuthApp = OAuthApp.defaults({
  /* set default constructor options */
})
```

**Why?**

Needed for the `octokit` module, see https://github.com/octokit/octokit.js/pull/15. The `Octokit` constructor needs to be set to `Octokit` exported by the `octokit` module, which includes several plugins.

**Alternatives you tried**

I could implement the defaults functionality within `octokit` but there it's the same amount of work, and `OAuthApp.defaults()` will be useful outside of `octokit`

### Additional contract requirements

- `OAuthApp.defaults(defaults)` returns a constructor that is a subclass of `OAuthApp`, so instances created from it are `instanceof OAuthApp`.
- When the returned constructor is instantiated, the provided `defaults` are merged with the constructor options, and the explicit constructor options take precedence over `defaults` when both specify the same option.
- `defaults` may contain any subset of the `OAuthApp` constructor options, including `allowSignup` and `Octokit`. When a custom `Octokit` is provided as a default, the resulting `app.octokit` is an instance of that `Octokit` class.
