Add pages argument to paginated methods
Currently there is no way to only return one page. The client follows `Next-Page` until it's gone through everything.

I suggest we do like `kinto-http.js` with a `pages` argument, defaulted to 1 if limit is specified.

Note that when limit is not specified in arguments (but defined on the server for example), we would follow every pages (`pages = float('inf')`)
