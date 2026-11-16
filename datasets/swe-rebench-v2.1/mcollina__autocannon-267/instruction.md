`idReplacement` not unique
Expected: `[<id>]` to be replaced with a unique id
Actual: `[<id>]` is not unique across requests

I ran the idReplacement sample with this modified handler, which parses the body and prints the email.
```nodejs
function handle(req, res) {
	let data = []
	req.on('data', chunk => {
		data.push(chunk)
	})
	req.on('end', () => {
		console.log(JSON.parse(data).email);
		res.end('hello world');
	})
}
```

I expected to see unique emails, but saw this instead (with `connections: 2, amount: 10`):
```
new-5DznV1MxQ8qpeLJIzpe+8A/0000000000@user.com
new-5DznV1MxQ8qpeLJIzpe+8A/0000000001@user.com
new-5DznV1MxQ8qpeLJIzpe+8A/0000000000@user.com
new-5DznV1MxQ8qpeLJIzpe+8A/0000000001@user.com
new-5DznV1MxQ8qpeLJIzpe+8A/0000000000@user.com
new-5DznV1MxQ8qpeLJIzpe+8A/0000000001@user.com
new-5DznV1MxQ8qpeLJIzpe+8A/0000000000@user.com
new-5DznV1MxQ8qpeLJIzpe+8A/0000000001@user.com
new-5DznV1MxQ8qpeLJIzpe+8A/0000000000@user.com
new-5DznV1MxQ8qpeLJIzpe+8A/0000000001@user.com
```
[HIDDEN]

I'm not sure if this is a problem with the example or a bug with the `idReplacement` feature.

The example, as is, doesn't produce unique email addresses. I did notice that adding: `setupRequest: req => req` to the request does generate a unique email address on each request.
```
new-x//7JAdiRZGiy4cAd5KNvg/0000000000@user.com
new-x//7JAdiRZGiy4cAd5KNvg/0000000001@user.com
new-x//7JAdiRZGiy4cAd5KNvg/0000000002@user.com
new-x//7JAdiRZGiy4cAd5KNvg/0000000003@user.com
new-x//7JAdiRZGiy4cAd5KNvg/0000000004@user.com
new-x//7JAdiRZGiy4cAd5KNvg/0000000005@user.com
new-x//7JAdiRZGiy4cAd5KNvg/0000000006@user.com
new-x//7JAdiRZGiy4cAd5KNvg/0000000007@user.com
new-x//7JAdiRZGiy4cAd5KNvg/0000000008@user.com
new-x//7JAdiRZGiy4cAd5KNvg/0000000009@user.com
```

Is `setupRequest` required to use `idReplacement`?

### Additional contract requirements

When `idReplacement` is enabled, each `[<id>]` placeholder in a request is replaced with a generated identifier, and identifiers are unique across requests. This behavior works without configuring a `setupRequest` callback.
