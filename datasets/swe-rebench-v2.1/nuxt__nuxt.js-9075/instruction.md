Allow specific names in publicRuntimeConfig
Hi and thanks for your work on Nuxt.

**Request**

As I mentioned in the official Nuxt `Discord`, can you please consider allowing users to use words/names such as `app` in project configuration?

It's short, strong meaning and definitely one of the most common for a configuration within a project. I think this approach that doesn't allow the use of such common names in the project configuration can be very confusing and problematic for debugging.

**Code example**

This worked fine until version `2.15.0`, so it's kind of a `breaking-change`:

```js
// nuxt.config.js

export default {
  publicRuntimeConfig: {
    // Doesn't work after version '2.14.12'
    app: {
      title: 'New Title',
      titleSeparator: '-',
      titleTemplate: 'Title Template',
      description: 'New Description',
    },
  },
}
```

**Suggestion**

As Daniel said in Discord chat:

> Nuxt is using the `app` namespace for internal dynamic config.

It might make more sense to use alternatives under the hood (in Nuxt core such as `_app` or `__app`) and allow users to use the normal versions (such as `app`).

**Other examples**

This is allowed in `Next.js`.

### Additional contract requirements

- Nuxt's internal dynamic configuration (`basePath`, `assetsPath`, `cdnURL`) must be exposed under the reserved key `_app` in `publicRuntimeConfig`, i.e. accessible as `$config._app` and `window.__NUXT__.config._app`. The `app` key must not be used for this internal configuration.
- A user-provided `publicRuntimeConfig.app` must be preserved unchanged and must not be merged with or overwritten by Nuxt's internal dynamic configuration.
