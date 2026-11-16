Watchers on Custom Resources throw RuntimeError("Session is closed") and permanently die
### Long story short

Operator starts up and runs normally as expected. After for running for some time some of the watch streams will throw a `RuntimeError("Session is closed")`. Once this happens that watch stream will never restart until the operator is restarted. This only appears to happen with custom resources (configmaps are fine).

### Kopf version

1.35.6

### Kubernetes version

v1.23.13 eks

### Python version

3.9.13

### Code

```python
import kopf
import kubernetes

@kopf.on.login()
def login_fn(**kwargs):
    return kopf.login_via_client(**kwargs)

@kopf.on.startup()
def operator_configuration(settings: kopf.OperatorSettings, **kwargs):
    settings.watching.server_timeout = 300
    settings.watching.client_timeout = 300
    settings.peering.name = "operator"
    settings.peering.mandatory = True
    settings.peering.stealth = True

@kopf.on.create("MyCustomResource")
@kopf.on.update("MyCustomResource")
def mycustomresource(**_):
    print("Im Alive!")
```


### Logs

```none
[01:55:09,761] asyncio              [DEBUG   ] Getting address info mycluster.eks.amazonaws.com:443, type=<SocketKind.SOCK_STREAM: 1>, flags=<AddressInfo.AI_ADDRCONFIG: 32> took 14.625ms: [(<AddressFamily.AF_INET: 2>, <SocketKind.SOCK_STREAM: 1>, 6, '', ('1.1.1.1', 443)), (<AddressFamily.AF_INET: 2>, <SocketKind.SOCK_STREAM: 1>, 6, '', ('2.2.2.2', 443))]
[01:55:09,842] asyncio              [DEBUG   ] <asyncio.sslproto.SSLProtocol object at 0x7f13b06945e0> starts SSL handshake
[01:55:10,002] asyncio              [DEBUG   ] <asyncio.sslproto.SSLProtocol object at 0x7f13b06945e0>: SSL handshake took 159.6 ms
[01:55:10,003] asyncio              [DEBUG   ] <asyncio.TransportSocket fd=8, family=AddressFamily.AF_INET, type=SocketKind.SOCK_STREAM, proto=6, laddr=('10.10.10.10', 41046), raddr=('1.1.1.1', 443)> connected to 1.1.1.1:443: (<asyncio.sslproto._SSLProtocolTransport object at 0x7f13b072b6a0>, <aiohttp.client_proto.ResponseHandler object at 0x7f13b079ae80>)
[01:55:36,674] kopf._core.engines.a [INFO    ] Re-authentication has been initiated.
[01:55:36,674] kopf.activities.auth [DEBUG   ] Activity 'login_fn' is invoked.
[01:55:36,751] asyncio              [DEBUG   ] <_SelectorSocketTransport fd=6 read=polling write=<idle, bufsize=0>> received EOF
[01:55:36,752] asyncio              [DEBUG   ] <asyncio.sslproto.SSLProtocol object at 0x7f13b06f4820> received EOF
[01:55:36,754] kopf._cogs.clients.w [ERROR   ] Request attempt #1/9 failed; will retry: GET https://mycluster.eks.amazonaws.com/apis/kopf.dev/v1/namespaces/mynamespace/kopfpeerings?watch=true&resourceVersion=13763208&timeoutSeconds=300 -> ServerDisconnectedError('Server disconnected')
[01:55:37,484] kopf.activities.auth [DEBUG   ] Client is configured via kubeconfig file.
[01:55:37,485] kopf.activities.auth [INFO    ] Activity 'login_fn' succeeded.
[01:55:37,485] kopf._core.engines.a [INFO    ] Re-authentication has finished.
[01:55:37,489] asyncio              [DEBUG   ] Get address info mycluster.eks.amazonaws.com:443, type=<SocketKind.SOCK_STREAM: 1>, flags=<AddressInfo.AI_ADDRCONFIG: 32>
[01:55:37,490] asyncio              [DEBUG   ] Getting address info mycluster.eks.amazonaws.com:443, type=<SocketKind.SOCK_STREAM: 1>, flags=<AddressInfo.AI_ADDRCONFIG: 32> took 0.790ms: [(<AddressFamily.AF_INET: 2>, <SocketKind.SOCK_STREAM: 1>, 6, '', ('1.1.1.1', 443)), (<AddressFamily.AF_INET: 2>, <SocketKind.SOCK_STREAM: 1>, 6, '', ('2.2.2.2', 443))]
[01:55:37,571] asyncio              [DEBUG   ] <asyncio.sslproto.SSLProtocol object at 0x7f13b05c57f0> starts SSL handshake
[01:55:37,730] asyncio              [DEBUG   ] <asyncio.sslproto.SSLProtocol object at 0x7f13b05c57f0>: SSL handshake took 159.4 ms
[01:55:37,731] asyncio              [DEBUG   ] <asyncio.TransportSocket fd=6, family=AddressFamily.AF_INET, type=SocketKind.SOCK_STREAM, proto=6, laddr=('10.10.10.10', 44038), raddr=('1.1.1.1', 443)> connected to 1.1.1.1:443: (<asyncio.sslproto._SSLProtocolTransport object at 0x7f13b078d460>, <aiohttp.client_proto.ResponseHandler object at 0x7f13b059a640>)
[01:55:37,756] kopf._cogs.clients.w [DEBUG   ] Request attempt #2/9: GET https://mycluster.eks.amazonaws.com/apis/kopf.dev/v1/namespaces/mynamespace/kopfpeerings?watch=true&resourceVersion=13763208&timeoutSeconds=300
[01:55:37,756] kopf._cogs.clients.w [DEBUG   ] Stopping the watch-stream for kopfpeerings.v1.kopf.dev in 'mynamespace'.
[01:55:37,759] kopf._core.reactor.o [ERROR   ] Peering observer for operator@mynamespace has failed: Session is closed
Traceback (most recent call last):
  File "/venv/lib/python3.9/site-packages/kopf/_cogs/aiokits/aiotasks.py", line 108, in guard
    await coro
  File "/venv/lib/python3.9/site-packages/kopf/_core/reactor/queueing.py", line 175, in watcher
    async for raw_event in stream:
  File "/venv/lib/python3.9/site-packages/kopf/_cogs/clients/watching.py", line 82, in infinite_watch
    async for raw_event in stream:
  File "/venv/lib/python3.9/site-packages/kopf/_cogs/clients/watching.py", line 186, in continuous_watch
    async for raw_input in stream:
  File "/venv/lib/python3.9/site-packages/kopf/_cogs/clients/watching.py", line 251, in watch_objs
    async for raw_input in api.stream(
  File "/venv/lib/python3.9/site-packages/kopf/_cogs/clients/api.py", line 200, in stream
    response = await request(
  File "/venv/lib/python3.9/site-packages/kopf/_cogs/clients/auth.py", line 45, in wrapper
    return await fn(*args, **kwargs, context=context)
  File "/venv/lib/python3.9/site-packages/kopf/_cogs/clients/api.py", line 78, in request
    response = await context.session.request(
  File "/venv/lib/python3.9/site-packages/aiohttp/client.py", line 400, in _request
    raise RuntimeError("Session is closed")
RuntimeError: Session is closed
[01:56:04,118] asyncio              [DEBUG   ] Get address info mycluster.eks.amazonaws.com:443, type=<SocketKind.SOCK_STREAM: 1>, flags=<AddressInfo.AI_ADDRCONFIG: 32>
[01:56:04,119] asyncio              [DEBUG   ] Getting address info mycluster.eks.amazonaws.com:443, type=<SocketKind.SOCK_STREAM: 1>, flags=<AddressInfo.AI_ADDRCONFIG: 32> took 0.731ms: [(<AddressFamily.AF_INET: 2>, <SocketKind.SOCK_STREAM: 1>, 6, '', ('1.1.1.1', 443)), (<AddressFamily.AF_INET: 2>, <SocketKind.SOCK_STREAM: 1>, 6, '', ('2.2.2.2', 443))]
[01:56:04,200] asyncio              [DEBUG   ] <asyncio.sslproto.SSLProtocol object at 0x7f13b05c58b0> starts SSL handshake
[01:56:04,359] asyncio              [DEBUG   ] <asyncio.sslproto.SSLProtocol object at 0x7f13b05c58b0>: SSL handshake took 158.7 ms
[01:56:04,360] asyncio              [DEBUG   ] <asyncio.TransportSocket fd=7, family=AddressFamily.AF_INET, type=SocketKind.SOCK_STREAM, proto=6, laddr=('10.10.10.10', 47442), raddr=('1.1.1.1', 443)> connected to 1.1.1.1:443: (<asyncio.sslproto._SSLProtocolTransport object at 0x7f13b07622e0>, <aiohttp.client_proto.ResponseHandler object at 0x7f13b06a14c0>)
[01:56:56,485] asyncio              [DEBUG   ] Get address info mycluster.eks.amazonaws.com:443, type=<SocketKind.SOCK_STREAM: 1>, flags=<AddressInfo.AI_ADDRCONFIG: 32>
[01:56:56,489] asyncio              [DEBUG   ] Getting address info mycluster.eks.amazonaws.com:443, type=<SocketKind.SOCK_STREAM: 1>, flags=<AddressInfo.AI_ADDRCONFIG: 32> took 3.814ms: [(<AddressFamily.AF_INET: 2>, <SocketKind.SOCK_STREAM: 1>, 6, '', ('1.1.1.1', 443)), (<AddressFamily.AF_INET: 2>, <SocketKind.SOCK_STREAM: 1>, 6, '', ('2.2.2.2', 443))]
[01:56:56,570] asyncio              [DEBUG   ] <asyncio.sslproto.SSLProtocol object at 0x7f13b05c5f10> starts SSL handshake
[01:56:56,730] asyncio              [DEBUG   ] <asyncio.sslproto.SSLProtocol object at 0x7f13b05c5f10>: SSL handshake took 159.4 ms
[01:56:56,730] asyncio              [DEBUG   ] <asyncio.TransportSocket fd=7, family=AddressFamily.AF_INET, type=SocketKind.SOCK_STREAM, proto=6, laddr=('10.10.10.10', 53874), raddr=('1.1.1.1', 443)> connected to 1.1.1.1:443: (<asyncio.sslproto._SSLProtocolTransport object at 0x7f13b06a1b20>, <aiohttp.client_proto.ResponseHandler object at 0x7f13b07624c0>)
```


### Additional information

This is an EKS cluster and is using aws eks get-token in the kubeconfig to authenticate.

Using aiohttp version 3.8.3
using kubernetes client version: 24.2.0
aws-cli/2.2.43 Python/3.8.8 (used by kubeconfig)

Not all operators watch streams die at the same time. This is not running in a container on the cluster but on a server outside of aws.

### Additional contract requirements

- Add a public method `Vault.invalidate(self, key: VaultKey, info: ConnectionInfo, *, exc: Optional[Exception] = None) -> None` in the module `kopf._cogs.structs.credentials` (class `Vault`). It returns `None`.
- The `info` argument identifies the exact credential entry to invalidate: if the vault's current entry for `key` is not the same `ConnectionInfo` instance as `info`, the current entry must be left untouched.
- When invalidation leaves the vault without any credentials, a re-authentication cycle is initiated. If an `exc` is provided and no credentials are obtained, `LoginError` is raised with `exc` as its cause.
- A request that fails because its HTTP session has been closed must be treated as a recoverable authentication failure: it must trigger credential invalidation and re-authentication instead of propagating the raw session-closed error.
