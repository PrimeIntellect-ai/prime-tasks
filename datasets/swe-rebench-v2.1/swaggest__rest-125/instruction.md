Header names case sensitivity
**Describe the bug**

According to

https://stackoverflow.com/questions/5258977/are-http-headers-case-sensitive

HTTP header names should be compared in a case-insensitive fashion.

With example input header definition

```
HeaderSecFetchSite string `header:"sec-fetch-site" required:"true"`
```

request with

```
Sec-Fetch-Site: same-origin
```
throws request validation failure with

```
"header:sec-fetch-site": [
      "missing value"
    ]
```

**Expected behavior**
Requests with any of below should be passed:

```
sec-fetch-site: same-origin
Sec-Fetch-Site: same-origin
sEc-fEtCh-sitE: same-origin
```

### Additional contract requirements

- When a required header is missing, use its canonicalized name in the validation error key. For a header tagged `X-In-HeAdEr`, the key must be `header:X-In-Header` and the message must be `missing value`.
