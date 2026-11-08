getCurrentHub: Incorrect deprecation notice?
Hey all!

I'm currently trying to close the Sentry connection on runtime whenever we detect an app update is available and the user has been prompted. As I'm lead to believe the current way to do so is as below, however, this prompts a deprecation notice to use `Sentry.getClient()` instead. This method does not exist, thus it seems this deprecation notice is incorrect.

```js
Sentry.getCurrentHub().getClient().close(0); // deprecated, but works
Sentry.getClient().close(0); // Sentry.getClient is not a function
```

 In contrast it does seem to work correctly when trying to close a Vue-specific instance of Sentry. In other words, this following prompts (correctly) to use the alternative:

```js
SentryVue.getCurrentHub().getClient().close(0); // deprecated, but works
SentryVue.getClient().close(0); // works just fine
```

While having to go through this many hoops to simply disable Sentry seems like a drag, that is a separate issue, though I would like to know whether this is correct, or whether only `Sentry` or `SentryVue` needs to be closed.

I'm currently using the following Sentry-relevant packages:

```json
"@sentry/capacitor": "0.18.0",
"@sentry/vite-plugin": "2.18.0",
"@sentry/vue": "7.114.0",
```

### Additional contract requirements

The Capacitor package's public entry point must expose `getClient`, so callers can retrieve the current Sentry client using the recommended top-level API.
