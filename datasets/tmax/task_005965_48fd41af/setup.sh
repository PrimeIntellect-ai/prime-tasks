#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
os.makedirs('/home/user/docs', exist_ok=True)
with open('/home/user/docs/a.txt', 'wb') as f:
    f.write(b'Document One: \x80 Euro sign')
with open('/home/user/docs/b.txt', 'wb') as f:
    f.write(b'Document Two: \x99 Trademark')
with open('/home/user/docs/c.txt', 'wb') as f:
    f.write(b'Document Three: \x85 Ellipsis')
"

    chmod -R 777 /home/user
