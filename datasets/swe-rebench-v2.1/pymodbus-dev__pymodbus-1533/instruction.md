Not possible to decode then encode a DiagnosticStatusResponse
### Versions

- Python: 3.8.6
- OS: Win10
- Pymodbus: 3.2.2
- Modbus Hardware (if used):

### Pymodbus Specific

- Client: tcp

### Description

It is not possible to decode, then encode a DiagnosticStatusResponse [HIDDEN] That means the message will not be processed in encode.

### Code and Logs

import pymodbus.diag_message

a = pymodbus.diag_message.DiagnosticStatusResponse()
a.decode(b"\x00\x01\x02\x03")
packet = a.encode()
print(packet)

Output: b'\x00\x01'

### Additional contract requirements

- After decoding a DiagnosticStatusResponse, encoding it must preserve the decoded payload; decoding and then encoding the same byte sequence must yield that sequence unchanged.
