#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/service.log
[2023-10-27 10:14:02] [INFO] Service started on port 8080
[2023-10-27 10:15:12] [DEBUG] Received incoming connection
[2023-10-27 10:15:12] [ERROR] Crash occurred while parsing packet. 
[2023-10-27 10:15:12] [ERROR] Raw Payload (base64): RkxBR3tzaWduZWRfaW50X2ZpeH0A3q2+7+P///8=
[2023-10-27 10:15:12] [TRACE] Exception in parse_packet: string index out of range
EOF

cat << 'EOF' > /home/user/parse_packet.py
import sys
import struct

def parse(data):
    # find magic header
    idx = data.find(b'\xde\xad\xbe\xef')
    if idx == -1:
        return "No magic found"

    # read 4-byte offset (little endian)
    offset = struct.unpack('<I', data[idx+4:idx+8])[0]

    # flag location is relative to the end of the offset field
    flag_idx = idx + 8 + offset

    if flag_idx < 0 or flag_idx >= len(data):
        return "Invalid flag index"

    # read string until null terminator
    end = data.find(b'\x00', flag_idx)
    if end == -1:
        end = len(data)

    return data[flag_idx:end].decode('ascii')

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python3 parse_packet.py <binary_file>")
        sys.exit(1)

    with open(sys.argv[1], 'rb') as f:
        data = f.read()
    print(parse(data))
EOF

chmod -R 777 /home/user
