Don't include a given request header when its value is null or undefined
If you do `got(url, { headers: { cookie: null } })`, the HTTP request has a header of `cookie: null` rather than not appearing at all. If you replace `null` with `undefined` then you get an error.

If a header is `null` or `undefined` the it shouldn't be added to the request headers.
