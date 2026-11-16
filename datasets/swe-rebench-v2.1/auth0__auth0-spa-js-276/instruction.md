getTokenSilently Lock is not released on error
### Description

Whenever `getTokenSilently` runs, the `GET_TOKEN_SILENTLY_LOCK_KEY` lock is acquired, which is then released before the function returns. However, the lock is not released if an error is thrown, which is a very common occurrence given that a `"login_required"` error is thrown within `runIframe` if the user does not have an SSO session.

Within our current app this causes a major issue: Loading the application from a clean state redirects the user to universal login immediately, but upon being redirected back to our application, the initial calls to our back-end are delayed by five seconds, as the lock value is still in localStorage, and our calls to `getTokenSilently` are delayed waiting for the lock timeout. Only once we successfully get an access token through `getTokenSilently` does auth0-spa-js remove the local store value and allow us to get the value in good time through the cache.

I'm certain the issue we're seeing is related to the lock, given that manually deleting the localStorage value while awaiting a response makes the app respond immediately.

### Reproduction

The easiest way to see this problem is to use the `npm run dev` script in auth0-spa-js
- When the test page loads, open dev tools
- Click "Get access token with no interaction"
- Note that an `Uncaught (in promise) "login_required"` error is logged to the console almost immediately.
- Click "Get access token with no interaction" again
- The second time, it will (normally, see below*) take around five seconds for the error to be logged to the console. There is also normally a `TypeError: Cannot read property 'close' of undefined` error logged alongside.

(* this reproduces _most_ times I carry these steps - I imagine because browser-tabs-lock has some sort of timeout handling that is invalidating the lock if you take a while to click the button the second time?)

### Environment

Reproduces with v1.4.2 and v1.5.0, but works fine with 1.3.2.

All my tests have been in Chrome, and our app uses Angular, although I don't think this is relevant.

### Suggested fix

[HIDDEN] I won't be able to try running our app with modified library code until next week, but please let me know if that would be helpful.

### Additional contract requirements

- After `getTokenSilently` acquires the `GET_TOKEN_SILENTLY_LOCK_KEY` lock, it must release the lock whether the operation succeeds or throws or rejects.
