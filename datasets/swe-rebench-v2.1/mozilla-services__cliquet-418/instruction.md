UUID4 generator regexp is too restrictive
The regexp is checking for UUID4 only (random ones).

In the case of using kinto as a key/value store the regexp is too restrictive.
It is the case for the payment app where we need to choose the record id (not randomly)

This is the way to generate a UUID from a given key.

```python
>>> my_object_id = 'Payment#ABCD'
>>> str(uuid.UUID(hashlib.md5(my_object_id).hexdigest()))
'fd800e8d-e8e9-3cac-f502-816cbed9bb6c'
```

```http
$ echo '{"data": {"title": "Test"}}' | http --verify no PUT https://kinto.dev.mozaws.net/v1/buckets/default/collections/tasks/records/fd800e8d-e8e9-3cac-f502-816cbed9bb6c --auth user:pass
HTTP/1.1 400 Bad Request
Connection: keep-alive
Content-Length: 167
Content-Type: application/json; charset=UTF-8
Date: Wed, 15 Jul 2015 08:28:10 GMT
Server: nginx/1.4.6 (Ubuntu)

{
    "code": 400,
    "details": [
        {
            "description": "Invalid record id",
            "location": "path",
            "name": null
        }
    ],
    "errno": 107,
    "error": "Invalid parameters",
    "message": "path: Invalid record id"
}
```
