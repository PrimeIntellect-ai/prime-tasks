PATCHing an account will change its password
If the `password` isn't provided in a `PATCH` to the accounts endpoint, the password will be automatically changed (to what?). Proof:

```
$ http GET https://kinto-dev.classea12.beta.gouv.fr/v1/accounts/mathieu+test@agopian.info --auth #<REDACTED>#

HTTP/1.1 200 OK
Access-Control-Expose-Headers: Pragma, Backoff, Alert, Expires, Content-Length, Cache-Control, Last-Modified, ETag, Retry-After
Cache-Control: no-cache, no-store
Content-Length: 275
Content-Type: application/json
Date: Fri, 22 Feb 2019 17:28:51 GMT
ETag: "1550772518933"
Last-Modified: Thu, 21 Feb 2019 18:08:38 GMT
Via: 1.1 alproxy
X-Content-Type-Options: nosniff

{
    "data": {
        "id": "mathieu+test@agopian.info",
        "last_modified": 1550772518933,
        "password": "$2b$12$S.foDbLWg75zCCOgTyb9POXmH67mcGkZin584hgEFyLYoCJcv2Bfa",
        "profile": "c8ba193d-f989-48ae-a95d-1941d2d44897",
        "validated": true
    },
    "permissions": {
        "write": [
            "account:mathieu+test@agopian.info"
        ]
    }
}
```

Now let's do a patch:

```
$ echo '{"data": { "foo": "bar"}}' | http PATCH https://kinto-dev.classea12.beta.gouv.fr/v1/accounts/mathieu+test@agopian.info --auth #<REDACTED>#

HTTP/1.1 200 OK
Access-Control-Expose-Headers: Retry-After, Backoff, Alert, Content-Length
Content-Length: 287
Content-Type: application/json
Date: Fri, 22 Feb 2019 17:40:07 GMT
ETag: "1550857207387"
Last-Modified: Fri, 22 Feb 2019 17:40:07 GMT
Via: 1.1 alproxy
X-Content-Type-Options: nosniff

{
    "data": {
        "foo": "bar",
        "id": "mathieu+test@agopian.info",
        "last_modified": 1550857207387,
        "password": "$2b$12$ShdFHEEyhRgDgfP4S8x6j.0otOhnKjbkca4yQ7IXQP.x6kHlvER.G",
        "profile": "c8ba193d-f989-48ae-a95d-1941d2d44897",
        "validated": true
    },
    "permissions": {
        "write": [
            "account:mathieu+test@agopian.info"
        ]
    }
}
```

Notice that we did not provide a `password` in the data, but still the final hash is not the same as the one we had before. It's now impossible to use this account, unless `PATCH`ing it again with an admin account, and this time around providing the password in the data.

### Additional contract requirements

When an account is updated with PATCH and the payload omits `password`, the account's existing password must be retained.
