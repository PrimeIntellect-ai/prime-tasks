[Bug] Dependency injection not working for HEAD requests
**Describe the bug**
Sanic automatically creates `HEAD` endpoints, but dependencies are not injected into these endpoints, causing 500 errors when users HEAD these endpoints.

**Screenshots**
![image](https://user-images.githubusercontent.com/6646473/202834223-30bdbf41-1ae9-4a8e-91a2-091ae194ac56.png)


**To Reproduce**
```python
from sanic import Sanic
from sanic.response import text

app = Sanic('test')

class Foo:
    pass

app.ext.add_dependency(Foo, lambda *_: None)

@app.route('/download')
async def handler(req, foo: Foo):
    return text('file')

if __name__ == '__main__':
    app.run(port=4321, debug=True)
```

And then `curl -I http://127.0.0.1:4321/download`.

It shows an HTTP 500 response. Sanic reports the following error:

`TypeError: handler() missing 1 required positional argument: 'foo'`

**Expected behavior**

It should receive an HTTP 200 response.

**Environment (please complete the following information):**
 - OS: Windows-10-10.0.19045-SP0
 - Browser: curl 7.83.1
 - Version: Sanic 22.9.0, sanic-ext 22.9.0, sanic-routing 22.8.0

**Additional context**
Many downloaders send a HEAD request before actually downloading. This bug breaks these downloaders.
