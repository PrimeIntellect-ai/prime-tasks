#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.txt
   Short line   
Short line

   こんにちは   
Hallo
Ciao
This is a sudden long string that should be an anomaly because it is quite long
This is a sudden long string that should be an anomaly because it is quite long
Test
Test2
Test3
Another very long UTF-8 string that will trigger anomaly: 👩🏽‍🚀👨🏽‍🚀
EOF

    chmod -R 777 /home/user
