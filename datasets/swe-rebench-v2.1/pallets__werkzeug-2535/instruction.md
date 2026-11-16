path converter doesn't redirect to trailing slash
It seems to me that the automatic redirect for URLs with trailing shlashes (like `/user` → `/user/`) described in [Flask docs](https://flask.palletsprojects.com/en/2.2.x/quickstart/#unique-urls-redirection-behavior) and [Werkzeug docs](https://werkzeug.palletsprojects.com/en/2.2.x/routing/#rule-format) does not work if you use PathConverter in an URL definition.

I have this straightforward Flask application to reproduce the problem:
```
from flask import Flask, Response

app = Flask(__name__)

@app.route('/')
@app.route('/<path:username>/')
def main(username=None):
    return Response(f"It works! Hello, {username}")
```
In werkzeug 2.1.2, it works as expected and if you send a request to `/user`, it redirects you via HTTP/308 to `/user/`. The log is:
```
* Running on http://127.0.0.1:5000 (Press CTRL+C to quit)
127.0.0.1 - - [12/Oct/2022 14:47:37] "GET / HTTP/1.1" 200 -
127.0.0.1 - - [12/Oct/2022 14:47:45] "GET /user HTTP/1.1" 308 -
127.0.0.1 - - [12/Oct/2022 14:47:45] "GET /user/ HTTP/1.1" 200 -
```
But when I use werkzeug 2.2.0, the same request gives me HTTP/404:
```
 * Running on http://127.0.0.1:5000 (Press CTRL+C to quit)
127.0.0.1 - - [12/Oct/2022 14:48:43] "GET /fooo HTTP/1.1" 404 -
```
I've tried a bisection of all the commits between those versions to see whether this was an intentional change or not and find that the difference has been introduced in: https://github.com/pallets/werkzeug/commit/5a7c0dec029d296a5e8131c8db51ce19e28c0c58

The workaround for this is to define both possible URLs for a single endpoint but it's not pretty. Also, the difference might cause problems if you still support Python 3.6 because pip installs older Flask and werkzeug for Python 3.6 where the redirect works fine and newer packages for Python 3.7+ where it does not.

Is this behavior intentional and if so, could you please add it to the documentation?
