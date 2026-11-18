#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/project /app/bin /tests/corpus/clean /tests/corpus/evil

    echo 'int helper() { return 42; }' > /home/user/project/utils.c
    echo 'int helper();' > /home/user/project/utils.h

    cat << 'EOF' > /home/user/project/Makefile
all:
	gcc utils.c -o libhelpers.so
EOF

    cat << 'EOF' > /app/bin/query_engine
#!/usr/bin/env python3
import sys
import base64

if len(sys.argv) > 1:
    try:
        decoded = base64.b64decode(sys.argv[1])
        reversed_bytes = decoded[::-1]
        print(reversed_bytes.hex())
    except:
        pass
EOF
    chmod +x /app/bin/query_engine

    cat << 'EOF' > /tests/corpus/clean/1.txt
POST /query HTTP/1.1
Content-Type: application/json

{"payload": "aGVsbG9fd29ybGQ="}
EOF

    cat << 'EOF' > /tests/corpus/evil/1.txt
POST /query HTTP/1.1
Content-Type: application/json

{"payload": "Y2F0IGBlY2hvIC9ldGMvcGFzc3dkYA=="}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /tests
