WebSocket requests from Firefox fail with a 400 error
Firefox issues their WebSocket requests with the following connection header:

    Connection: keep-alive, Upgrade

While Chrome and other browsers do:

    Connection: Upgrade

The WebSocket routing logic needs to be made more robust to accept the general format of the Connection header. I will work on this fix and submit a PR in the next few days.

Environment:

- Python version: Any
- Werkzeug version: 2.0.0
