Extract key `data` on batch body?
While debugging something else, I found out that a request forged by kinto-http contained an extra key `data`.

 `request.body` (on the server side):

```json
{
	"requests": [{
		"body": {
			"data": {
				"driverVersionComparator": "LESS_THAN_OR_EQUAL",
				"driverVersion": "6.1.7601.18328",
				"vendor": "0x1002",
				"blockID": "g1239",
				"enabled": true,
				"feature": "DIRECT3D_10_LAYERS",
				"devices": ["0x4396"],
				"id": "cf217981-2c42-76bf-df19-4324a194a075",
				"details": {
					"why": "test",
					"who": "test",
					"name": "GFX1-Val",
					"bug": "https://bugzilla.mozilla.org/show_bug.cgi?id=838845",
					"created": "2016-10-18T09:29:16Z"
				},
				"os": "All",
				"featureStatus": "BLOCKED_DRIVER_VERSION"
			}
		},
		"path": "/buckets/staging/collections/gfx/records/cf217981-2c42-76bf-df19-4324a194a075",
		"method": "PATCH"
	}, {...}, {...}],
	"data": {}
}
```

### Additional contract requirements

When no data value is supplied, the request payload must not acquire an empty top-level `data` field. This also applies when a batch payload contains a top-level `requests` field.
A PUT request with no supplied payload fields must still be sent with an empty JSON object.
