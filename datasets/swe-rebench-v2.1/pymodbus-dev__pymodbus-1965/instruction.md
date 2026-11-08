ModbusSocketFramer bug when multiple modbus messages are received in 1 tcp payload
<!--
Before opening a new issue, make sure you do the following:

- Check that your issue isn't already filed: https://github.com/pymodbus-dev/pymodbus/issues
- Check the discussions forum https://github.com/pymodbus-dev/pymodbus/discussions
- Prepare a short, runnable example that reproduce the issue with the latest development version of Pymodbus
-->

### Versions

- Python: 3.8.x
- OS: Linux
- Pymodbus: 3.6.3
- Modbus Hardware (if used): modbus TCP

### Pymodbus Specific

- Server: tcp - async

### Description

When receiving multiple modbus frames in a single tcp frame, pymodbus throws an error. This happens cause of a misscalculation.
[HIDDEN]
This doesn't happen when there is only 1 modbus packet inside a TCP frame cause in python `my_list[:length] == my_list[:length+1]` is True.

### Code and Logs

Added some prints inside the framer funtions to debug

```python
datagram_received

2024-01-22 22:54:03,852 DEBUG logging:103 recv: 0x4 0x83 0x0 0x0 0x0 0x6 0x1 0x3 0x11 0x4d 0x0 0x32 0x4 0x84 0x0 0x0 0x0 0x6 0x1 0x3 0x30 0x1 0x0 0x4 0x4 0x85 0x0 0x0 0x0 0x6 0x1 0x3 0x31 0x5 0x0 0x11 old_data:  addr=None
2024-01-22 22:54:03,852 DEBUG logging:103 Handling data: 0x4 0x83 0x0 0x0 0x0 0x6 0x1 0x3 0x11 0x4d 0x0 0x32 0x4 0x84 0x0 0x0 0x0 0x6 0x1 0x3 0x30 0x1 0x0 0x4 0x4 0x85 0x0 0x0 0x0 0x6 0x1 0x3 0x31 0x5 0x0 0x11
2024-01-22 22:54:03,852 DEBUG logging:103 Processing: 0x4 0x83 0x0 0x0 0x0 0x6 0x1 0x3 0x11 0x4d 0x0 0x32 0x4 0x84 0x0 0x0 0x0 0x6 0x1 0x3 0x30 0x1 0x0 0x4 0x4 0x85 0x0 0x0 0x0 0x6 0x1 0x3 0x31 0x5 0x0 0x11
getFrame 13 7 6
_process b'\x03\x11M\x002\x04'
2024-01-22 22:54:03,853 DEBUG logging:103 Factory Request[ReadHoldingRegistersRequest': 3]
5 b'\x11M\x002\x04'
Traceback (most recent call last):
  File ".../MyModbusServer.py", line 111, in handle
    await self.inner_handle()
  File ".../MyModbusServer.py", line 101, in inner_handle
    self._framer.processIncomingPacket(
  File ".../pymodbus/framer/base.py", line 139, in processIncomingPacket
    self.frameProcessIncomingPacket(single, callback, slave, **kwargs)
  File ".../pymodbus/framer/socket_framer.py", line 141, in frameProcessIncomingPacket
    self._process(callback, tid)
  File ".../pymodbus/framer/socket_framer.py", line 147, in _process
    if (result := self.decoder.decode(data)) is None:
  File ".../pymodbus/factory.py", line 183, in decode
    return self._helper(message)
  File ".../pymodbus/factory.py", line 216, in _helper
    request.decode(data[1:])
  File ".../pymodbus/register_read_message.py", line 49, in decode
    self.address, self.count = struct.unpack(">HH", data)
struct.error: unpack requires a buffer of 4 bytes
2024-01-22 22:54:03,855 DEBUG logging:103 Client Disconnection server_listener due to unpack requires a buffer of 4 bytes
```

### Additional contract requirements

- The socket framer must correctly process multiple Modbus messages received in a single TCP payload without truncating them or raising a decoding error.
