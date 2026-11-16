client.initialize_client() doesn't throw an exception when connection failed to establish
When trying to initialize connection to an invalid address, error is being printed to screen but exception isn't thrown and code continues running.

Would expect to be able to catch an error and decide what I want to do with it (continue running or exit)

Error:
```
Unleash Client registration failed due to exception: Invalid URL 'foo/client/register': No schema supplied. Perhaps you meant http://foo/client/register?
Traceback (most recent call last):
  File "/usr/local/lib/python3.9/dist-packages/UnleashClient/api/register.py", line 45, in register_client
    resp = requests.post(url + REGISTER_URL,
  File "/usr/local/lib/python3.9/dist-packages/requests/api.py", line 119, in post
    return request('post', url, data=data, json=json, **kwargs)
  File "/usr/local/lib/python3.9/dist-packages/requests/api.py", line 61, in request
    return session.request(method=method, url=url, **kwargs)
  File "/usr/local/lib/python3.9/dist-packages/requests/sessions.py", line 528, in request
    prep = self.prepare_request(req)
  File "/usr/local/lib/python3.9/dist-packages/requests/sessions.py", line 456, in prepare_request
    p.prepare(
  File "/usr/local/lib/python3.9/dist-packages/requests/models.py", line 316, in prepare
    self.prepare_url(url, params)
  File "/usr/local/lib/python3.9/dist-packages/requests/models.py", line 390, in prepare_url
    raise MissingSchema(error)
requests.exceptions.MissingSchema: Invalid URL 'foo/client/register': No schema supplied. Perhaps you meant http://foo/client/register?
Unleash Client feature fetch failed due to exception: Invalid URL 'foo/client/features': No schema supplied. Perhaps you meant http://foo/client/features?
Traceback (most recent call last):
  File "/usr/local/lib/python3.9/dist-packages/UnleashClient/api/features.py", line 42, in get_feature_toggles
    resp = requests.get(base_url,
  File "/usr/local/lib/python3.9/dist-packages/requests/api.py", line 76, in get
    return request('get', url, params=params, **kwargs)
  File "/usr/local/lib/python3.9/dist-packages/requests/api.py", line 61, in request
    return session.request(method=method, url=url, **kwargs)
  File "/usr/local/lib/python3.9/dist-packages/requests/sessions.py", line 528, in request
    prep = self.prepare_request(req)
  File "/usr/local/lib/python3.9/dist-packages/requests/sessions.py", line 456, in prepare_request
    p.prepare(
  File "/usr/local/lib/python3.9/dist-packages/requests/models.py", line 316, in prepare
    self.prepare_url(url, params)
  File "/usr/local/lib/python3.9/dist-packages/requests/models.py", line 390, in prepare_url
    raise MissingSchema(error)
requests.exceptions.MissingSchema: Invalid URL 'foo/client/features': No schema supplied. Perhaps you meant http://foo/client/features?
Unable to get feature flag toggles, using cached provisioning.
Cache Exception: '/client/features'
Unleash client does not have cached features. Please make sure client can communicate with Unleash server!
```
