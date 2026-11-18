#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron systemd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/migration
    mkdir -p /home/user/.config/systemd/user/
    cat << 'EOF' > /home/user/migration/worker.py
#!/usr/bin/env python3
import os
import time

out_dir = os.environ.get("WORKER_DATA_DIR", "/tmp")
out_file = os.path.join(out_dir, "data.txt")

with open(out_file, "w") as f:
    f.write(f"Processed at {time.time()}\n")
EOF
    chmod +x /home/user/migration/worker.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
