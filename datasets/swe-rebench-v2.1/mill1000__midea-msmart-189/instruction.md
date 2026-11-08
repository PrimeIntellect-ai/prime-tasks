Device should remain online if at least one response is received during refresh
When refreshing the device state a number of commands are sent
https://github.com/mill1000/midea-msmart/blob/294e74b412ea86f47999875a222c08aed1120709/msmart/device/AC/device.py#L459-L482

However, each must be responded to otherwise the device can be marked offline,

We should instead consider the device online if any of the commands get a response.

### Additional contract requirements

- The public method `Device._send_command(command: Frame) -> list[bytes]` in module
  `msmart.base_device` serializes the given command with `tobytes()` and transmits the
  serialized bytes over the device's LAN connection.
- The returned list is empty when no response is received and non-empty when one or more
  responses are received, so callers can distinguish a response from no response.
- On a network timeout the method logs a warning whose message matches `Network timeout .*`
  and returns an empty list. On a protocol error it logs an error whose message matches
  `Network error .*` and returns an empty list.
