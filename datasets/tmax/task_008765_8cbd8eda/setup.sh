#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/chat_logs.txt
[2023-12-01T08:00:00Z] <charlie>    good    morning   everyone!
[2023-12-01T08:05:22Z] <alice>    I   love   café   au   lait
[2023-12-01T08:12:00Z] <BØB> SYSTEM   FAILURE   IMMINENT
[2023-12-01T08:15:30Z] <charlie> nevermind,   it    works   now.
[2023-12-01T08:20:00Z] <dæmon>    restarting     services...
[2023-12-01T08:25:00Z] <alice>   wait,   my   café   spilled!
[2023-12-01T08:30:00Z] <ZØE>   héllo   wørld
EOF

    chmod -R 777 /home/user
