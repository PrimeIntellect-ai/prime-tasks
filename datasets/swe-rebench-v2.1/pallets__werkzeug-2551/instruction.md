json: Return 415 if wrong Content-Type
Amending to #2355:
When a request contains a wrong or no Content-Type, not 400 Bad Request should be returned but more precisely [415 Unsupported Media Type](https://httpwg.org/specs/rfc9110.html#status.415). This greatly helps tracking down the reason of malformed requests.

### Replicate:
Using Flask
```
from flask import Flask, request
app = Flask(__name__)
@app.post('/')
def test():
    return request.json
```
```
curl -i localhost:5000 -d '{"json": "test"}'
HTTP/1.1 400 BAD REQUEST
Server: Werkzeug/2.2.2 Python/3.10.6
Date: Thu, 24 Nov 2022 15:44:58 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 193
Connection: close

<!doctype html>
<html lang=en>
<title>400 Bad Request</title>
<h1>Bad Request</h1>
<p>Did not attempt to load JSON data because the request Content-Type was not &#39;application/json&#39;.</p>
```

### Expected behaviour
```
curl -i localhost:5000 -d '{"json": "test"}'
HTTP/1.1 415 UNSUPPORTED MEDIA TYPE
Server: Werkzeug/2.2.2 Python/3.10.6
Date: Thu, 24 Nov 2022 15:47:46 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 215
Connection: close

<!doctype html>
<html lang=en>
<title>415 Unsupported Media Type</title>
<h1>Unsupported Media Type</h1>
<p>Did not attempt to load JSON data because the request Content-Type was not &#39;application/json&#39;.</p>
```

Environment:

- Python version: 3.10.6
- Werkzeug version: 2.2.2
