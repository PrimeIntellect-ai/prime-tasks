Hostname with api in name broken for`websocket_call`
Currently `websocket_call` does [some hackery](https://github.com/kubernetes-incubator/client-python/blob/master/kubernetes/client/ws_client.py#L211-L216) to generate the websocket URL:
```python
    # switch protocols from http to websocket
    url = url.replace('http://', 'ws://')
    url = url.replace('https://', 'wss://')

    # patch extra /
    url = url.replace('//api', '/api')
```

Websocket calls are broken when the URL includes the string `'api'` in the hostname. For example:`api.k8s.staging.mydomain.com` will result in the following error:
```
kubernetes.client.rest.ApiException: (0)
Reason: hostname is invalid
```

A good solution would be to have proper URL parsing in place and replacing paths, rather than working off a pure string
