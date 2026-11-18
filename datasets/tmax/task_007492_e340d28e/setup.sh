#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os

log_data = '''=== SESSION START: sess_alpha ===
[INFO] Processing started
[TRACE]
  some
  garbage
[METRICS] BytesTransferred: 1024
[TRACE]
  more garbage
[METRICS] BytesTransferred: 2048
=== SESSION END ===
=== SESSION START: sess_beta ===
[INFO] Processing started
[METRICS] BytesTransferred: 500
=== SESSION END ===
=== SESSION START: sess_gamma ===
[METRICS] BytesTransferred: 8000
[METRICS] BytesTransferred: 12
=== SESSION END ===
'''

with open('/home/user/bloated_log.txt', 'w', encoding='utf-16le') as f:
    f.write(log_data)
"

    chmod -R 777 /home/user
