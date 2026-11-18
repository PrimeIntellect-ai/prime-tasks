#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw.jsonl
{"ts":"2023-10-01T10:00:00Z","user":"admin","key":"database","val":"mysql"}
{"ts":"2023-10-01T10:05:00Z","user":"admin","key":"password","val":"super\u0053ecret\u0021"}
{"ts":"2023-10-01T10:00:00Z","user":"admin","key":"database","val":"mysql"}
{"ts":"2023-10-01T10:10:00Z","user":"alice","key":"api_key","val":"sk_test_\u0031\u0032\u0033"}
{"ts":"2023-10-01T10:15:00Z","user":"bob","key":"theme","val":"dark"}
{"ts":"2023-10-01T10:15:00Z","user":"bob","key":"theme","val":"dark"}
{"ts":"2023-10-01T10:20:00Z","user":"charlie","key":"greeting","val":"hello\u0020world"}
EOF

    chmod -R 777 /home/user
