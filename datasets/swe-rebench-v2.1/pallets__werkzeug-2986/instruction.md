`str(request.headers)` is empty

Greetings from changedetection.io, thanks for your work!

Our tests started failing, turns out related (somehow) to Werkzeug 3.1.0

We have a test endpoint that is looking at the headers that were sent with a request

https://github.com/dgtlmoon/changedetection.io/blob/7029d10f8bd22ac2379fcfe70bf57b67ebee69fc/changedetectionio/tests/util.py#L231

for example

```
    # Where we POST to as a notification
    @live_server.app.route('/test_notification_endpoint', methods=['POST', 'GET'])
    def test_notification_endpoint():
        p = request.headers
```

but `request.headers` is always empty (by empty i mean contains `\r\n`), downgrading to `3.0.6` fixed it (from `3.1.0`)



Tried python 3.10, 3.11, and 3.12

```
pytest                       7.4.4
pytest-flask                 1.3.0
Werkzeug                     3.0.6 (this version is OK)
```

Strangely, all other variables in `request` look perfectly OK, tcpdump shows the headers are being sent without problem, HTTP_ type vars in the request look OK too

thanks!
