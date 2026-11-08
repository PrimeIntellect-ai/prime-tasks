getTokenSilently is slow even with cache hit.
### Description

Calling Auth0Client's getTokenSilently function takes about 50ms on my MacBook Pro even in cases where the token is retrieved from the cache. With 4x CPU throttling it's about 150ms which can seriously degrade the user experience.

### Reproduction

I'm calling the following function during data fetching.
`const token = await auth0Client.getTokenSilently();`
It takes about 50ms on my computer. When I rolled back to my auth0-spa-js dependency from 1.6.2 to 1.3.2 it went down to 0.2ms on average.
I think this performance issue is caused by the locking mechanism which was introduced in this PR:
https://github.com/auth0/auth0-spa-js/pull/238

### Proposed fix
I think the lock should be acquired only if there was no cache hit. That would eliminate the lag in almost every cases. If there's no cache hit, this 50ms won't be very significant.

[HIDDEN]
https://github.com/auth0/auth0-spa-js/blob/48a88d708980213063f12c64c0da29a126f411f7/src/Auth0Client.ts#L304

### Environment

- **Version of this library used:** 1.6.2
- **Other relevant versions (language, server software, OS, browser):** Google Chrome, MacOS

### Additional contract requirements

- When `getTokenSilently` finds a cached token, it must return that token without acquiring the lock.
