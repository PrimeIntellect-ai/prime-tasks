#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/chat_logs.txt
2023-10-01T12:00:00Z | U01 | Hello world!
2023-10-01T12:00:15Z | U02 | Apple is tasty.
2023-10-01T12:00:30Z | U03 | Helo world!
2023-10-01T12:01:10Z | U04 | Hello world!
2023-10-01T12:05:00Z | U05 | こんにちは
2023-10-01T12:05:10Z | U06 | こんちには
2023-10-01T12:05:20Z | U07 | Goodbye!
2023-10-01T12:05:30Z | U08 | こんにちは!
2023-10-01T12:05:30Z | U05 | こんにちは!
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
