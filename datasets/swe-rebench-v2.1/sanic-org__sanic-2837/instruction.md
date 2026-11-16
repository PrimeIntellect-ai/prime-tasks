Cookie totally breaks if the client sets a bare cookie
### Is there an existing issue for this?

- [X] I have searched the existing issues

### Describe the bug

A cookie may be not in the `key=value` format. For example. if the JS code runs `document.cookie = "bad"`, it becomes:

![image](https://github.com/sanic-org/sanic/assets/6646473/c9a1f53c-62bf-4516-9003-49fed08773dc)

I don't know how to call it. I will use the term "bare cookie" in this report. In the following requests with a bare cookie, the Cookie HTTP header becomes: `Cookie: key=value; bad`

![image](https://github.com/sanic-org/sanic/assets/6646473/536bdf38-61ad-4f31-bb78-6c7844433298)

It seems that Sanic cannot parse the header with bare cookies, and will throw all cookies (including the legimit `key=value` pair) away. See the code snippet below.

### Code snippet

```python
from sanic import Sanic
from sanic.response import html, text

app = Sanic("test")
app.config.AUTO_EXTEND = False

@app.get("/")
async def route1(request):
    return html('<script>document.cookie="key=value"; document.cookie="bad"; location.href="/fire";</script>')

@app.get("/fire")
async def route2(request):
    return text(f'''
        headers = {request.headers.get("Cookie")}
        key = {request.cookies.get("key", "none")}
    ''')

if __name__ == '__main__':
    app.run(port=4321, debug=True)
```

Then visit `http://127.0.0.1:4321/` in Chrome. The page shows:

```
headers = key=value; bad
key = none
```

### Expected Behavior

The page should show:

```
headers = key=value; bad
key = value
```

### How do you run Sanic?

As a script (`app.run` or `Sanic.serve`)

### Operating System

Windows

### Sanic Version

22.12.0

### Additional context

I am using the latest stable Chrome (117.0.5938.150) to reproduce this.

### Additional contract requirements

A bare cookie token is represented as a cookie with an empty name and the token as its value. It is available through `request.cookies.get("")`.
