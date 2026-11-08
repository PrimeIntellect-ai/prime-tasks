Multiple Set-Cookie not working in hook.js/ts in the Build. Only setting the first cookie.
**Sveltekit version: 1.0.0.next.405
Azure-SWA-adapter-version: ^0.10.0**

In hooks.js if we are sending multiple cookies in response header like this:
```
response.headers.append('Set-Cookie', cookie1);
response.headers.append('Set-Cookie', cookie2);
response.headers.append('Set-Cookie', cookie3);
```
The response header during dev environment looks like this:
```
Set-cookie : cookie1
Set-cookie : cookie2
Set-cookie : cookie3
```
and it sets all cookies.

But when testing the build either with SWA CLI or deployed app. The response header looks like this:

`Set-Cookie: Cookie1; Cookie2; Cookie3`
This only takes Cookie1 into account and leave the rest.

I have deployed my app on Vercel with Serverless Function  using Vercel adapter and on Azure with Nodejs adapter. On both , the `Set-Cookie` behave as expected and set all the cookies and response header also looks like this:
```
Set-cookie : cookie1
Set-cookie : cookie2
Set-cookie : cookie3
```

### Additional contract requirements

- Add a public function `splitCookiesFromHeaders(headers)` in `files/headers.js`. It accepts a `Headers` instance and returns an object with two properties:
  - `headers`: a plain object containing every header entry except `set-cookie`, keyed by the header name as exposed by `Headers` (lower-cased) with the value unchanged.
  - `cookies`: an array of parsed cookie objects, one per `Set-Cookie` value. Each object has at least `name` and `value`, and includes attributes such as `expires` (a `Date`) when present. When several cookies are concatenated into a single `Set-Cookie` header string, each of them must be parsed into its own object.
- In the build output, a rendered response that sets multiple cookies must set all of them, not only the first. The generated serverless function must expose every cookie from the rendered response's `Set-Cookie` headers as a `cookies` array on its HTTP response object, and must not include `set-cookie` among the response `headers`.
