AuthorizedSession attempts to refresh token when no refresh token was provided
Using google-auth 1.4.1

If `google.auth.transport.requests.AuthorizedSession` is used with an expired token, it will automatically try to refresh the token even if no refresh token was provided to the credentials object.
This causes the unreadable exception
```TransportError: Invalid URL 'None': No schema supplied. Perhaps you meant http://None?```

There should be a sanity check for a non-existing refresh token before any refresh attempt is made. A proper exception should be raised if the token is expired.

Sample code:
```python
import google.oauth2.credentials
from google.auth.transport.requests import AuthorizedSession
credentials = google.oauth2.credentials.Credentials('an_expired_token')
authed_session = AuthorizedSession(credentials)
response = authed_session.get('some_url_requiring_authentication')
```

Traceback:
```
  File "/usr/lib/python3.6/site-packages/requests/sessions.py", line 521, in get
    return self.request('GET', url, **kwargs)
  File "/usr/lib/python3.6/site-packages/google/auth/transport/requests.py", line 218, in request
    self.credentials.refresh(auth_request_with_timeout)
  File "/usr/lib/python3.6/site-packages/google/oauth2/credentials.py", line 126, in refresh
    self._client_secret))
  File "/usr/lib/python3.6/site-packages/google/oauth2/_client.py", line 237, in refresh_grant
    response_data = _token_endpoint_request(request, token_uri, body)
  File "/usr/lib/python3.6/site-packages/google/oauth2/_client.py", line 106, in _token_endpoint_request
    method='POST', url=token_uri, headers=headers, body=body)
  File "/usr/lib/python3.6/site-packages/google/auth/transport/requests.py", line 124, in __call__
    six.raise_from(new_exc, caught_exc)
  File "<string>", line 3, in raise_from
google.auth.exceptions.TransportError: Invalid URL 'None': No schema supplied. Perhaps you meant http://None?
```

### Additional contract requirements

When `google.oauth2.credentials.Credentials.refresh` is called without a refresh token, it must raise `google.auth.exceptions.RefreshError` before making a refresh request.
