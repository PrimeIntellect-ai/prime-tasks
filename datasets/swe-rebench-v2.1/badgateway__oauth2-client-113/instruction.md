Calling `oAuth2Fetch.fetch()` immediately after invoking constructor causes race condition with async IIFE invoking `getStoredToken`
This following code fails because getStoredToken is always invoked as an async function, meaning that `fetchWrapper.fetch()` will be called before `getStoredToken()` has even been called. See [this](https://github.com/badgateway/oauth2-client/blob/674630d3f912b978c73cd500601b1d0cdf0e71e0/src/fetch-wrapper.ts#L70) async IIFE. By the time the `fetchWrapper.fetch()` is called, the private property `fetchWrapper.token` is still null, so `getToken()` attempts to refresh it, which fails, invoking `refreshToken()` which attempts to refresh the non-existent token, which fails invoking `getNewToken()` which also fails, finally invoking `onError`, which prompts the user to log in again. When this is finished, control returns to the async IIFE, which finally sets the token to the correct value, and the next time `fetchWrapper.fetch()` is invoked, it behaves correctly. I have verified this using the debugger in Chrome DevTools. [HIDDEN] Until a fix is released, I have a temporary workaround, but it is quite hacky, so I would appreciate a stable fix.

**Problematic Code**
```ts
const fetchWrapper = new OAuth2Fetch({
    client,
    getNewToken: () => {
      return null; // Fail this step, we don't want to log out until the user does so explicitly
    },
    storeToken,
    getStoredToken,
    onError: (error) => {
      // Prompt the user to log in again
    },
  });

const res = await fetchWrapper.fetch(...)
```

**Temporary workaround**
```ts
let ready = false;

const initialiseFetchWrapper = async () => {
  const fetchWrapper = new OAuth2Fetch({
    client,

    getNewToken: () => {
      return null; // Fail this step, we don't want to log out until the user does so explicitly
    },

    storeToken,

    getStoredToken,

    onError: (error) => {
      if (ready) {/* Prompt user to log in */}
    },
  });
  try {
    await fetchWrapper.getToken();
  } catch {
    // Ignore we expect this to error the first time
  }
  ready = true;
  return fetchWrapper;
};

let _fetchWrapper: OAuth2Fetch | null = null;

// We defer initialisation until the first call to fetchAuthenticated to ensure that initialisation has been completed
const getFetchWrapper = async () => {
  if (!_fetchWrapper) {
    _fetchWrapper = await initialiseFetchWrapper();
  }

  return _fetchWrapper;
};
```

### Additional contract requirements

- A request made immediately after construction must wait for configured stored-token retrieval to complete before making its token decision. It must not treat the token as absent while retrieval is pending.
