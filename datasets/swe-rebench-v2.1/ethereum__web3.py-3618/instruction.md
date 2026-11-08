construct_event_filter_params improperly formats addresses as lists of lists
### What happened?

called `event.get_logs(from_block=from_block, to_block=block_current)` with the instantiated parent contract having `address` set to a list of addresses.

This raised an exception about address validity. It shouldn't have.

### Code that produced the error

```python
contract = contract_factory.ServiceNodeContribution(address[0])
NewContribution = contract.events.NewContribution
NewContribution.address = address
for recent in await NewContribution.get_logs(from_block=from_block, to_block=block_current):
    print(recent)
```

### Full error output

```shell
Traceback (most recent call last):
  File "src/app_events.py", line 19, in <module>
    init_ws_event_scanner(config)
  File "/home/aerilym/git/ssb/src/web3client/event_ws.py", line 516, in init_ws_event_scanner
    asyncio.run(start(config))
  File "/usr/lib/python3.12/asyncio/runners.py", line 194, in run
    return runner.run(main)
           ^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/asyncio/runners.py", line 118, in run
    return self._loop.run_until_complete(task)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/asyncio/base_events.py", line 687, in run_until_complete
    return future.result()
           ^^^^^^^^^^^^^^^
  File "/home/aerilym/git/ssb/src/web3client/event_ws.py", line 512, in start
    await monitor
  File "/home/aerilym/git/ssb/src/web3client/event_ws.py", line 472, in monitor_events
    await scan_past_queued_events(w3)
  File "/home/aerilym/git/ssb/src/web3client/event_ws.py", line 420, in scan_past_queued_events
    for recent in await past_event.event.get_logs(from_block=from_block, to_block=block_current):
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/aerilym/git/sent-staking-backend/.venv/lib/python3.12/site-packages/web3/contract/async_contract.py", line 181, in get_logs
    _filter_params = self._get_event_filter_params(
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/aerilym/git/sent-staking-backend/.venv/lib/python3.12/site-packages/eth_utils/decorators.py", line 29, in _wrapper
    return self.method(obj, *args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/aerilym/git/sent-staking-backend/.venv/lib/python3.12/site-packages/web3/contract/base_contract.py", line 311, in _get_event_filter_params
    _, event_filter_params = construct_event_filter_params(
                             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/aerilym/git/sent-staking-backend/.venv/lib/python3.12/site-packages/web3/_utils/filters.py", line 117, in construct_event_filter_params
    for addr in filter_params["address"]:
        ^^^^^^^^^^^^^^^^^^^^^^
  File "/home/aerilym/git/sent-staking-backend/.venv/lib/python3.12/site-packages/web3/_utils/validation.py", line 179, in validate_address
    raise Web3TypeError(f"Address {value} must be provided as a string")
web3.exceptions.Web3TypeError: Address ['0xdA5ba...6763e', '0xFC7880C60...2295122F', '0x36eeDdB5...a71a0698E5B462f299Dec', '0xC212293A2d8255...813cC3FDd7a3ee'] must be provided as a string
```

### Fill this section in if you know how this could or should be fixed

This suggestion is implemented in #3618

[HIDDEN]

### web3 Version

7.8.0

### Python Version

3.12.3

### Operating System

linux

### Output from `pip freeze`

```shell
aiodns==3.1.1
aiohappyeyeballs==2.4.4
aiohttp==3.10.11
aiosignal==1.3.1
annotated-types==0.7.0
async-timeout==4.0.3
attrs==24.2.0
bitarray==3.0.0
black==24.8.0
blinker==1.7.0
certifi==2023.11.17
cffi==1.17.1
chardet==5.2.0
charset-normalizer==3.3.2
ckzg==2.0.1
click==8.1.7
colorama==0.4.6
coloredlogs==15.0.1
cryptography==40.0.2
cytoolz==1.0.1
distro==1.9.0
eth-account==0.13.4
eth-hash==0.7.0
eth-keyfile==0.8.1
eth-keys==0.6.1
eth-rlp==2.1.0
eth-typing==5.0.0
eth-utils==5.0.0
eth_abi==5.1.0
Flask==3.0.3
frozenlist==1.5.0
hexbytes==1.2.1
humanfriendly==10.0
idna==3.8
iniconfig==2.0.0
itsdangerous==2.1.2
Jinja2==3.1.4
MarkupSafe==2.1.5
multidict==6.1.0
mypy-extensions==1.0.0
oxenc @ file:///home/aerilym/git/ssb/dep-tmp/oxenc
oxenmq @ file:///home/aerilym/git/ssb/dep-tmp/oxenmq
packaging==23.2
parsimonious==0.10.0
pathspec==0.12.1
pillow==10.2.0
platformdirs==4.2.2
pluggy==1.5.0
propcache==0.2.1
protobuf==4.21.12
psycopg==3.2.4
psycopg-pool==3.2.4
py-solc-x==2.0.3
pycares==4.5.0
pycparser==2.22
pycryptodome==3.21.0
pycryptodomex==3.20.0
pydantic==2.9.2
pydantic_core==2.23.4
PyNaCl==1.5.0
pyOpenSSL==23.2.0
pytest==8.3.4
pyunormalize==16.0.0
regex==2024.9.11
requests==2.32.3
rlp==4.0.1
setuptools==68.1.2
simplejson==3.19.3
toolz==1.0.0
types-requests==2.32.0.20240905
typing_extensions==4.10.0
urllib3==2.0.7
uWSGI==2.0.28
web3==7.8.0
websockets==13.1
Werkzeug==3.0.4
wheel==0.42.0
yarl==1.16.0
```

### Additional contract requirements

Event-filter construction must accept address lists and combine supplied address and contract-address values into a usable, flat address filter. A single resulting address may be represented either as one address or as a one-item list. Address values must still be validated, and unsupported address input types must still be rejected with the existing value-error behavior.
