Come up with a better way of setting cookies.
Currently, to set cookies on a response you have to use the `safehttp.Header.SetCookie` method which takes a `http.Cookie`. All other ways to modify header values block the modification of the `Set-Cookie` header.

I suggest that we remove the `safehttp.Header.SetCookie` method, implement a `safehttp.Cookie` type with safe defaults and add a `SetCookie` method to `safehttp.ResponseWriter`.

### Additional contract requirements

- `safehttp.NewCookie(name, value)` creates a cookie whose defaults have the Secure and HttpOnly attributes enabled and SameSite set to Lax.
- `safehttp.ResponseWriter.SetCookie` adds the provided `safehttp.Cookie` to the response's Set-Cookie headers.
- `safehttp.Header` does not expose a `SetCookie` method. Ordinary header modification methods continue to block changes to Set-Cookie.
