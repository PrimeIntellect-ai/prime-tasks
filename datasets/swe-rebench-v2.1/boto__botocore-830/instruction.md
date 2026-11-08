Dynamodb local uses HTTPS instead of HTTP
In our endpoints.json we have:

```
            "local": {
              "hostname": "localhost:8000",
              "protocols": [
                "http"
              ],
              "credentialScope": {
                "region": "us-east-1"
              }
            }

```

However, creating a client with this region will use HTTPS:

```
>>> import botocore.session
>>> botocore.session.get_session().create_client('dynamodb', 'local').list_tables()
...
botocore.vendored.requests.exceptions.SSLError: [SSL: UNKNOWN_PROTOCOL] unknown protocol (_ssl.c:581)
```

My best guess is that we're not honoring the `protocol` key from endpoints.json when creating clients.
