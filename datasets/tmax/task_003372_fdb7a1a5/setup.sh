#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import base64
regex = b"^/api/v2/update\\\\?token=[a-f0-9]{8}"
b64_regex = base64.b64encode(regex)
elf_content = b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00" + b"\x00"*1000 + b"C2_BEACON: " + b64_regex + b"\x00" + b"\x00"*100
with open("/home/user/suspicious.elf", "wb") as f:
    f.write(elf_content)
'

    cat << 'EOF' > /home/user/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0000] "GET /index.html HTTP/1.1" 200 1024
10.0.5.55 - - [10/Oct/2023:13:56:00 -0000] "GET /api/v2/update?token=deadbeef HTTP/1.1" 200 452
172.16.0.2 - - [10/Oct/2023:13:57:00 -0000] "GET /api/v2/update?token=123 HTTP/1.1" 404 120
10.0.5.55 - - [10/Oct/2023:13:58:00 -0000] "POST /api/v2/update?token=a1b2c3d4 HTTP/1.1" 200 90
192.168.1.100 - - [10/Oct/2023:13:59:00 -0000] "GET /api/v2/update?token=00000000 HTTP/1.1" 200 12
203.0.113.1 - - [10/Oct/2023:14:00:00 -0000] "GET /api/v2/update?token=invalid1 HTTP/1.1" 400 50
EOF

    chmod 644 /home/user/suspicious.elf
    chmod 644 /home/user/access.log

    chmod -R 777 /home/user
