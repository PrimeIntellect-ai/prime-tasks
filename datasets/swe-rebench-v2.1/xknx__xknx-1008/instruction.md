AttributeError: 'Keyring' object has no attribute 'backbone'
Hi.

My ETS generates a .knxkeys file that doesn't have a "backbone" parameter:

```
<?xml version="1.0" encoding="utf-8"?>
<Keyring Project="Apartment" CreatedBy="ETS 5.7.4 (Build 1093)" Created="2022-08-09T15:53:32" Signature="yaIT..." xmlns="http://knx.org/xml/keyring/1">
  <Interface Type="Tunneling" Host="1.1.251" UserID="2" Password="HIDDEN" IndividualAddress="HIDDEN" Authentication="HIDDEN" />
  <Interface Type="Tunneling" Host="1.1.251" UserID="3" Password="HIDDEN" IndividualAddress="HIDDEN" Authentication="HIDDEN" />
  <Interface Type="Tunneling" Host="1.1.251" UserID="4" Password="HIDDEN" IndividualAddress="HIDDEN" Authentication="HIDDEN" />
  <Interface Type="Tunneling" Host="1.1.251" UserID="5" Password="HIDDEN" IndividualAddress="HIDDEN" Authentication="HIDDEN" />
  <Devices>
    <Device IndividualAddress="1.1.251" SequenceNumber="24" />
  </Devices>
</Keyring>
```

Because of that i get the following error:

```
There was an error during loading the knxkeys file.
Traceback (most recent call last):
  File "/opt/homebrew/lib/python3.9/site-packages/xknx/secure/keyring.py", line 316, in load_key_ring
    keyring.decrypt(password)
  File "/opt/homebrew/lib/python3.9/site-packages/xknx/secure/keyring.py", line 299, in decrypt
    if self.backbone is not None:
AttributeError: 'Keyring' object has no attribute 'backbone'
Traceback (most recent call last):
  File "/opt/homebrew/lib/python3.9/site-packages/xknx/secure/keyring.py", line 316, in load_key_ring
    keyring.decrypt(password)
  File "/opt/homebrew/lib/python3.9/site-packages/xknx/secure/keyring.py", line 299, in decrypt
    if self.backbone is not None:
AttributeError: 'Keyring' object has no attribute 'backbone'

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/Users/max/Projects/KNX/example_telegram_monitor.py", line 69, in <module>
    asyncio.run(main(sys.argv[1:]))
  File "/opt/homebrew/Cellar/python@3.9/3.9.13_1/Frameworks/Python.framework/Versions/3.9/lib/python3.9/asyncio/runners.py", line 44, in run
    return loop.run_until_complete(main)
  File "/opt/homebrew/Cellar/python@3.9/3.9.13_1/Frameworks/Python.framework/Versions/3.9/lib/python3.9/asyncio/base_events.py", line 647, in run_until_complete
    return future.result()
  File "/Users/max/Projects/KNX/example_telegram_monitor.py", line 65, in main
    await monitor(address_filters)
  File "/Users/max/Projects/KNX/example_telegram_monitor.py", line 47, in monitor
    await xknx.start()
  File "/opt/homebrew/lib/python3.9/site-packages/xknx/xknx.py", line 128, in start
    await self.knxip_interface.start()
  File "/opt/homebrew/lib/python3.9/site-packages/xknx/io/knxip_interface.py", line 69, in start
    await self._start()
  File "/opt/homebrew/lib/python3.9/site-packages/xknx/io/knxip_interface.py", line 105, in _start
    keyring: Keyring = load_key_ring(
  File "/opt/homebrew/lib/python3.9/site-packages/xknx/secure/keyring.py", line 321, in load_key_ring
    raise InvalidSecureConfiguration() from exception
xknx.exceptions.exception.InvalidSecureConfiguration
```

I get the same error in the standalone version of XKNX and in Home Assistant when using the "TCP with IP Secure" connection mode.

My code:

```
    connection_config = ConnectionConfig(
        connection_type=ConnectionType.TUNNELING_TCP_SECURE,
        gateway_ip="192.168.11.24",
        secure_config=SecureConfig(
            user_id=3,
            knxkeys_file_path="/Users/max/KNX/Deployment/Apartment.knxkeys",
            knxkeys_password="HIDDEN",
        ),
    )

    xknx = XKNX(connection_config=connection_config, daemon_mode=True)
```

As a temporary fix i've applied the following patch:

```
--- xknx/secure/keyring.py	2022-08-09 19:49:28.000000000 +0300
+++ xknx/secure/keyring_fixed.py	2022-08-09 20:27:51.000000000 +0300
@@ -233,6 +233,7 @@

     def __init__(self) -> None:
         """Initialize the Keyring."""
+        [HIDDEN]
         self.interfaces = []
         self.devices = []
         self.group_addresses = []
```

- [X] using xknx standalone
- [X] using Home-Assistant knx integration

**Version information:**
- Standalone xknx: 0.22.1
- xknx / Home-Assistant release with the issue: 2022.7.7

**KNX installation:**
ETS 5.7.4
KNX IP Interface: MDT SCN-IP000.03

### Additional contract requirements

- Loading a `.knxkeys` file that contains no `Backbone` element, using the correct keyring password, succeeds and decrypts the interface passwords. It must not fail with an `AttributeError` or raise `InvalidSecureConfiguration`.
