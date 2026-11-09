#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/traffic.txt
POST /api/v1/system_command HTTP/1.1
Host: 10.0.0.5:8080
User-Agent: Mozilla/5.0 (compatible; NetAdmin/1.0)
Accept: */*
Cookie: session_id=99481; Auth-Token=1a1740110943087e1516590f086e0c4a
Content-Length: 43
Content-Type: application/json

{"cmd": "status", "target": "all_routers"}
EOF

    python3 -c '
with open("/home/user/handler.elf", "wb") as f:
    f.write(b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00")
    f.write(b"\x00" * 120)
    f.write(b"Some random binary data here...")
    f.write(b"\x00\x00\x00XOR_KEY_tr4ff1c!\x00\x00\x00")
    f.write(b"More dummy sections...")
'
    chmod +x /home/user/handler.elf

    chmod -R 777 /home/user
