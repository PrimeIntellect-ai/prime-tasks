Cookies with expiry time set to epoch zero are matched and not expired
If the server sends a cookie with expiry time set to epoch zero (1970-01-01T00:00:00.000Z), the cookie is then returned in ``getCookies(url)`` even though "expire" is set to true (the default)

[HIDDEN]
https://github.com/salesforce/tough-cookie/blob/1a71340594beac95c4ea10fefe4eb79fdfead5c2/lib/cookie/cookieJar.ts#L940

### Additional contract requirements

- When expiration checking is enabled (the default), `getCookies(url)` must omit a cookie whose expiry time is epoch zero.
