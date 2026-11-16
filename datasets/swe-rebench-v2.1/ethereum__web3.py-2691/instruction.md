Async concurrency regression with 5.29.0
* Version: 5.29.0
* Python: 3.9.7
* OS: macos

### What was wrong?

Async code with the AsyncHTTPProvider hangs in 5.29.0; previously worked fine in 5.28.0.

(Shoddy) code sample:
```py
import asyncio
from web3 import Web3, AsyncHTTPProvider
from web3.eth import AsyncEth
from web3.net import AsyncNet
from web3.middleware import async_geth_poa_middleware

networks = {
    'ARBITRUM' : 'https://arb1.arbitrum.io/rpc',
    'AURORA'   : 'https://mainnet.aurora.dev',
    'AVAX'     : 'https://rpc.ankr.com/avalanche/',
    'BSC'      : 'https://bscrpc.com',
    'CELO'     : 'https://rpc.ankr.com/celo/',
    'CRONOS'   : 'https://evm-cronos.crypto.org',
    'FANTOM'   : 'https://rpc.ankr.com/fantom/',
    'FUSE'     : 'https://rpc.fuse.io/',
    'HARMONY'  : 'https://rpc.ankr.com/harmony/',
    'HECO'     : 'https://http-mainnet.hecochain.com',
    'METIS'    : 'https://andromeda.metis.io/?owner=1088',
    'MOONBEAM' : 'https://rpc.api.moonbeam.network',
    'MOONRIVER': 'https://rpc.api.moonriver.moonbeam.network/',
    'POLYGON'  : 'https://polygon-rpc.com/'
}

async def load_networks():
    async def connect_rpc(network, uri):
        rpc = Web3(
            AsyncHTTPProvider(
                uri,
                request_kwargs={'timeout': 10},
            ),
            modules={'eth': AsyncEth, 'net': AsyncNet},
            middlewares=[]
        )
        rpc.middleware_onion.inject(async_geth_poa_middleware, layer=0)

        try:
            chain_id = await rpc.eth.chain_id
            print(network, chain_id)
        except Exception as e:
            print(network, e)

    tasks = [connect_rpc(chain, info) for chain, info in networks.items()]
    await asyncio.gather(*tasks)

if __name__ == "__main__":
    asyncio.run(load_networks())
```

With 5.28.0, the output is as expected.
```
BSC 56
AURORA 1313161554
POLYGON 137
HECO 128
MOONBEAM 1284
MOONRIVER 1285
ARBITRUM 42161
METIS 1088
AVAX 43114
FANTOM 250
CELO 42220
HARMONY 1666600000
FUSE 122
CRONOS 25
```

When updating to 5.29.0, the output hangs. When I abort the program, the error output references a session cache lock (edited for readability)

```
KeyboardInterrupt
Task exception was never retrieved
future: <Task finished name='Task-1' coro=<load_networks() done, defined at []/async_test.py:25> exception=KeyboardInterrupt()>
Traceback (most recent call last):
  File "[]/async_test.py", line 49, in <module>
    asyncio.run(load_networks())
  File "[]/python3.9/asyncio/runners.py", line 47, in run
    _cancel_all_tasks(loop)
  File "[]/python3.9/asyncio/runners.py", line 63, in _cancel_all_tasks
    loop.run_until_complete(
  File "[]/python3.9/asyncio/base_events.py", line 629, in run_until_complete
    self.run_forever()
  File "[]/python3.9/asyncio/base_events.py", line 596, in run_forever
    self._run_once()
  File "[]/python3.9/asyncio/base_events.py", line 1890, in _run_once
    handle._run()
  File "[]/python3.9/asyncio/events.py", line 80, in _run
    self._context.run(self._callback, *self._args)
  File "[]/async_test.py", line 46, in load_networks
    await asyncio.gather(*tasks)
  File "[]/python3.9/asyncio/runners.py", line 44, in run
    return loop.run_until_complete(main)
  File "[]/python3.9/asyncio/base_events.py", line 629, in run_until_complete
    self.run_forever()
  File "[]/python3.9/asyncio/base_events.py", line 596, in run_forever
    self._run_once()
  File "[]/python3.9/asyncio/base_events.py", line 1890, in _run_once
    handle._run()
  File "[]/python3.9/asyncio/events.py", line 80, in _run
    self._context.run(self._callback, *self._args)
  File "[]/async_test.py", line 38, in connect_rpc
    chain_id = await rpc.eth.chain_id
  File "[]/python3.9/site-packages/web3/eth.py", line 360, in chain_id
    return await self._chain_id()  # type: ignore
  File "[]/python3.9/site-packages/web3/module.py", line 72, in caller
    result = await w3.manager.coro_request(method_str,
  File "[]/python3.9/site-packages/web3/manager.py", line 213, in coro_request
    response = await self._coro_make_request(method, params)
  File "[]/python3.9/site-packages/web3/manager.py", line 160, in _coro_make_request
    return await request_func(method, params)
  File "[]/python3.9/site-packages/web3/middleware/formatting.py", line 137, in middleware
    response = await make_request(method, params)
  File "[]/python3.9/site-packages/web3/providers/async_rpc.py", line 80, in make_request
    raw_response = await async_make_post_request(
  File "[]/python3.9/site-packages/web3/_utils/request.py", line 113, in async_make_post_request
    session = await _get_async_session(endpoint_uri)
[HIDDEN]
KeyboardInterrupt
Unclosed client session
client_session: <aiohttp.client.ClientSession object at 0x106ffafd0>
```

I do see that some SessionCache code [is included in 5.29.0](https://github.com/ethereum/web3.py/compare/v5.28.0...v5.29.0#diff-da1c04440e0604ceb9d314eec7151604f68036eaf4e6206f78f7aa38e36b0a65). My use case may be quite different than what was intended by the Session Cache and is likely related to my report in https://github.com/ethereum/web3.py/pull/2254 (ack, my apologies for not following up on that, @kclowes!).

### Additional contract requirements

- `web3._utils.request.SessionCache` holds at most `size` entries. Inserting a new key into a full cache evicts the least-recently inserted entry; the evicted entries are returned as a mapping from key to value (or `None` when nothing was evicted).
- Concurrent requests made through `AsyncHTTPProvider` in the reported use case must complete rather than hang.
