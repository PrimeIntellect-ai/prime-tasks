#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/data.csv
text,label
"The quick brown fox",A
"He is in the room",A
"An apple a day",B
"There is an error",B
"In the end",A
"Another hero",B
"Theather is great",A
"An interesting era",B
"Here in the inn",A
"Heroic antics",B
EOF

    chmod -R 777 /home/user
