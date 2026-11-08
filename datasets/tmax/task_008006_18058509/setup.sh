#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/queries.txt
2023-10-01T10:00:00Z|U102|Café!
2023-10-01T10:05:00Z|U102|café
2023-10-01T09:00:00Z|U101|HELLO world...
2023-10-01T09:30:00Z|U101|hello WORLD
2023-10-01T11:00:00Z|U103|東京??
2023-10-01T11:05:00Z|U103|東京
2023-10-01T11:10:00Z|U103|TOKYO
2023-10-01T08:15:00Z|U101|apple pie!
2023-10-01T08:15:00Z|U104|El Niño!!!
2023-10-01T08:20:00Z|U104|el niño
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
