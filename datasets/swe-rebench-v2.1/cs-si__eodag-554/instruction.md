Connection timeout bug in search API
**Describe the bug**

No result from provider 'creodias' due to an error during the search.

`urllib3.exceptions.ConnectTimeoutError: (<urllib3.connection.HTTPSConnection object at 0x7f0614fa07f0>, 'Connection to finder.creodias.eu timed out. (connect timeout=5)')`

Timeout error is not properly handled and propagated back. The error (len() of None) appears already inside the eodag code:

[HIDDEN]

**Code To Reproduce**

`all_products = session.search_all(**search_criteria)` -> with the specific search and creodias provider for example.

**Output**

```
[2022-11-14 23:38:30,795][eodag.core][INFO] - Searching product type 'S2_MSI_L1C' on provider: creodias
[2022-11-14 23:38:30,795][eodag.core][INFO] - Iterate search over multiple pages: page #1
[2022-11-14 23:38:30,795][eodag.plugins.search.qssearch][INFO] - Sending search request: https://finder.creodias.eu/resto/api/collections/Sentinel2/search.json?startDate=2019-05-01T00:00:00&completionDate=2019-10-01T00:00:00&geometry=POLYGON ((9.1010 46.6489, 9.0945 46.6490, 9.0946 46.6534, 9.1011 46.6534, 9.1010 46.6489))&productType=L1C&maxRecords=2000&page=1
[2022-11-14 23:38:35,883][eodag.plugins.search.qssearch][ERROR] - Skipping error while searching for creodias QueryStringSearch instance:
Traceback (most recent call last):
  File ".../lib/python3.9/site-packages/urllib3/connection.py", line 174, in _new_conn
    conn = connection.create_connection(
  File ".../lib/python3.9/site-packages/urllib3/util/connection.py", line 95, in create_connection
    raise err
  File ".../lib/python3.9/site-packages/urllib3/util/connection.py", line 85, in create_connection
    sock.connect(sa)
socket.timeout: timed out

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File ".../lib/python3.9/site-packages/urllib3/connectionpool.py", line 703, in urlopen
    httplib_response = self._make_request(
  File ".../lib/python3.9/site-packages/urllib3/connectionpool.py", line 386, in _make_request
    self._validate_conn(conn)
  File ".../lib/python3.9/site-packages/urllib3/connectionpool.py", line 1042, in _validate_conn
    conn.connect()
  File ".../lib/python3.9/site-packages/urllib3/connection.py", line 358, in connect
    self.sock = conn = self._new_conn()
  File ".../lib/python3.9/site-packages/urllib3/connection.py", line 179, in _new_conn
    raise ConnectTimeoutError(
urllib3.exceptions.ConnectTimeoutError: (<urllib3.connection.HTTPSConnection object at 0x7f0614fa07f0>, 'Connection to finder.creodias.eu timed out. (connect timeout=5)')

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File ".../lib/python3.9/site-packages/requests/adapters.py", line 489, in send
    resp = conn.urlopen(
  File ".../lib/python3.9/site-packages/urllib3/connectionpool.py", line 787, in urlopen
    retries = retries.increment(
  File ".../lib/python3.9/site-packages/urllib3/util/retry.py", line 592, in increment
    raise MaxRetryError(_pool, url, error or ResponseError(cause))
urllib3.exceptions.MaxRetryError: HTTPSConnectionPool(host='finder.creodias.eu', port=443): Max retries exceeded with url: /resto/api/collections/Sentinel2/search.json?startDate=2019-05-01T00:00:00&completionDate=2019-10-01T00:00:00&geometry=POLYGON%20((9.1010%2046.6489,%209.0945%2046.6490,%209.0946%2046.6534,%209.1011%2046.6534,%209.1010%2046.6489))&productType=L1C&maxRecords=2000&page=1 (Caused by ConnectTimeoutError(<urllib3.connection.HTTPSConnection object at 0x7f0614fa07f0>, 'Connection to finder.creodias.eu timed out. (connect timeout=5)'))

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File ".../lib/python3.9/site-packages/eodag/plugins/search/qssearch.py", line 864, in _request
    response = requests.get(url, timeout=HTTP_REQ_TIMEOUT, **kwargs)
  File ".../lib/python3.9/site-packages/requests/api.py", line 73, in get
    return request("get", url, params=params, **kwargs)
  File ".../lib/python3.9/site-packages/requests/api.py", line 59, in request
    return session.request(method=method, url=url, **kwargs)
  File ".../lib/python3.9/site-packages/requests/sessions.py", line 587, in request
    resp = self.send(prep, **send_kwargs)
  File ".../lib/python3.9/site-packages/requests/sessions.py", line 701, in send
    r = adapter.send(request, **kwargs)
  File ".../lib/python3.9/site-packages/requests/adapters.py", line 553, in send
    raise ConnectTimeout(e, request=request)
requests.exceptions.ConnectTimeout: HTTPSConnectionPool(host='finder.creodias.eu', port=443): Max retries exceeded with url: /resto/api/collections/Sentinel2/search.json?startDate=2019-05-01T00:00:00&completionDate=2019-10-01T00:00:00&geometry=POLYGON%20((9.1010%2046.6489,%209.0945%2046.6490,%209.0946%2046.6534,%209.1011%2046.6534,%209.1010%2046.6489))&productType=L1C&maxRecords=2000&page=1 (Caused by ConnectTimeoutError(<urllib3.connection.HTTPSConnection object at 0x7f0614fa07f0>, 'Connection to finder.creodias.eu timed out. (connect timeout=5)'))
[2022-11-14 23:38:35,888][eodag.core][INFO] - No result from provider 'creodias' due to an error during search. Raise verbosity of log messages for details
```

```
File ".../sentinel_api.py", line 49, in search_products
    all_products = session.search_all(**search_criteria)
  File ".../lib/python3.9/site-packages/eodag/api/core.py", line 1099, in search_all
    for page_results in self.search_iter_page(
  File ".../lib/python3.9/site-packages/eodag/api/core.py", line 953, in search_iter_page
    products, _ = self._do_search(
  File ".../lib/python3.9/site-packages/eodag/api/core.py", line 1339, in _do_search
    res, nb_res = search_plugin.query(count=count, **kwargs)
  File ".../lib/python3.9/site-packages/eodag/plugins/search/qssearch.py", line 341, in query
    eo_products = self.normalize_results(provider_results, **kwargs)
  File ".../lib/python3.9/site-packages/eodag/plugins/search/qssearch.py", line 677, in normalize_results
    [HIDDEN]
TypeError: object of type 'NoneType' has no len()
```

**Environment:**
 - Python version: 3.9
 - EODAG version: 2.6.0

**Additional context**

The above error appeared in a large-scale search for 50k different searches. The error appeared on a specific search, after 10s of thousands of successful searches.

### Additional contract requirements

- A connection timeout during a provider search must not make `search_all` fail with the reported secondary `TypeError`; the timeout must be handled as a failed search rather than surfacing as a length-of-`None` error.
