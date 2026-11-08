convert timeout type when loaded from environment variable
Following #973,
```py
import os
from eodag import EODataAccessGateway
os.environ["EODAG__HYDROWEB_NEXT__SEARCH__TIMEOUT"] = "10"

dag = EODataAccessGateway()
dag.search_all(productType="HYDROWEB_RIVERS")
```
raises
```
Traceback (most recent call last):
  File "/home/msordi/git/git-hysope2/deployment/misc/stac/test_download_hydroweb0.py", line 75, in <module>
    search_results = dag.search_all(
  File "/home/msordi/.local/lib/python3.10/site-packages/eodag/api/core.py", line 1219, in search_all
    self.fetch_product_types_list()
  File "/home/msordi/.local/lib/python3.10/site-packages/eodag/api/core.py", line 638, in fetch_product_types_list
    provider_ext_product_types_conf = self.discover_product_types(
  File "/home/msordi/.local/lib/python3.10/site-packages/eodag/api/core.py", line 699, in discover_product_types
    ] = search_plugin.discover_product_types()
  File "/home/msordi/.local/lib/python3.10/site-packages/eodag/plugins/search/qssearch.py", line 286, in discover_product_types
    response = QueryStringSearch._request(
  File "/home/msordi/.local/lib/python3.10/site-packages/eodag/plugins/search/qssearch.py", line 800, in _request
    response = requests.get(
  File "/usr/lib/python3/dist-packages/requests/api.py", line 76, in get
    return request('get', url, params=params, **kwargs)
  File "/usr/lib/python3/dist-packages/requests/api.py", line 61, in request
    return session.request(method=method, url=url, **kwargs)
  File "/usr/lib/python3/dist-packages/requests/sessions.py", line 544, in request
    resp = self.send(prep, **send_kwargs)
  File "/usr/lib/python3/dist-packages/requests/sessions.py", line 657, in send
    r = adapter.send(request, **kwargs)
  File "/usr/lib/python3/dist-packages/requests/adapters.py", line 435, in send
    timeout = TimeoutSauce(connect=timeout, read=timeout)
  File "/usr/lib/python3/dist-packages/urllib3/util/timeout.py", line 103, in __init__
    self._connect = self._validate_timeout(connect, "connect")
  File "/usr/lib/python3/dist-packages/urllib3/util/timeout.py", line 158, in _validate_timeout
    raise ValueError(
ValueError: Timeout value connect was 10, but it must be an int, float or None.
```

- [x] `timeout` loaded from environment variable needs to be converted to `float`

### Additional contract requirements

- `eodag.config.override_config_from_env(config)` is a public function that reads the process environment for variables whose names start with `EODAG__`, resolves the provider and nested configuration attributes they target, and updates the given configuration mapping in place.
- Environment values are converted to the Python type declared for the targeted configuration field. In particular, `search.timeout` is a `float` and `search.pagination` is a mapping that may contain an integer `start_page`.
- `override_config_from_env` returns `None`.
- When a value cannot be converted to the declared type, the original string value is kept and a warning is logged; no exception is raised.
