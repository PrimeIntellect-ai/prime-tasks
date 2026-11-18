#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_small.txt
  Hello, World!!! This is a TEST.  Data-cleaning is... FUN? 123 
EOF

    head -c 5000000 /dev/urandom | base64 > /home/user/raw_large.txt

    chmod -R 777 /home/user
