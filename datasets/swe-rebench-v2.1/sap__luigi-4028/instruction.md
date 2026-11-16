Option to reset expiration(-soon) check interval
in oauth2 plugin, when the onAuthExpireSoon event is fired, the check interval is cleared without an easy option to set it again, because the initial assumption was that a full auth redirect flow will eventually take place and thus the whole app state is reset anyway. There are now customer use cases where a new token can be obtained while staying at the page, which makes it necessary to establish new check intervals.

### Additional contract requirements

- Add a public method `AuthLayerSvc.resetExpirationChecks()` that takes no arguments. When an IDP provider instance is configured, it invokes that instance's `resetExpirationChecks` function; when no provider instance is configured it does nothing. Any error thrown by the provider's `resetExpirationChecks` function propagates to the caller.
- The oauth2 IDP provider must expose a `resetExpirationChecks()` method that re-establishes the token expiration and expiration-soon checks after they have been cleared.
