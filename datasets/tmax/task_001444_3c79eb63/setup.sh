#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_logs.py
import random

lines = [
    "1700000000|0x7F000001|U1|GET|150|200", # Valid. Hour 472222, 127.0.0.1
    "1700001000|0x7F000001|U1|POST|200|201", # Valid. Hour 472222, 127.0.0.1
    "1700002000|0xC0A80101|U2|GET|50|404", # Valid. Hour 472222, 192.168.1.1
    "1700003000|0xC0A80101|U2|GET|-10|200", # Invalid time
    "1700004000|0xC0A80101|U3|GET|100|600", # Invalid status
    "1700005000|0xC0A80101|U3|GET|100|OK", # Invalid status
    "1700005000|0x08080808|U1|GET|300|500", # Valid. Hour 472223, 8.8.8.8
    "1700006000|0xFFFFFFFF|U4|PUT|0|599", # Valid. Hour 472223, 255.255.255.255
    "1700007000|0x00000000|U4|GET|10|200" # Valid. Hour 472224, 0.0.0.0
]

with open("/home/user/raw_logs.txt", "w") as f:
    f.write("\n".join(lines) + "\n")
EOF
    python3 /tmp/setup_logs.py
    chown user:user /home/user/raw_logs.txt

    chmod -R 777 /home/user
