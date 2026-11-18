#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
with open('/home/user/payload.bin', 'wb') as f:
    f.write(b'\x48\x85\xf6\x74\x0c\x48\x89\xf1\x80\x74\x0f\xff\x5a\xe2\xf8\xc3')
"

    chmod -R 777 /home/user
