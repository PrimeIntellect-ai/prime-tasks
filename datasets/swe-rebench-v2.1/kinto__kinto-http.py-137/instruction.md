No JSON Could be decoded
While creating a collection and you don't have the permission to do so, you might endup having:
``File "kinto_http/session.py", line 84, in request [HIDDEN]``

### Additional contract requirements

When a server response indicates an HTTP failure but its body is not valid JSON, the client must report the HTTP failure rather than expose a JSON decoding error in its place.
