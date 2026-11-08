#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/service_dump

    cat << 'EOF' > /home/user/service_dump/crash_trace.txt
Thread 1 (Thread 0x7f8b9c3f7700 (LWP 1234)):
#0  0x00007f8ba1b2a45c in parse_multipart_form_data () from /opt/app/lib/libhttp.so
#1  0x00007f8ba1b2b881 in handle_upload_request () from /opt/app/lib/libhttp.so
#2  0x00007f8ba1b1933a in http_router_dispatch () from /opt/app/lib/libcore.so
#3  0x00007f8ba1b1a555 in worker_thread_main () from /opt/app/lib/libcore.so
#4  0x00007f8b9f8d56db in start_thread () from /lib/x86_64-linux-gnu/libpthread.so.0
#5  0x00007f8b9f60871f in clone () from /lib/x86_64-linux-gnu/libc.so.6
EOF

    cat << 'EOF' > /tmp/gen_logs.py
import random
from datetime import datetime, timedelta

with open("/home/user/service_dump/service.log", "w") as f:
    start1 = datetime(2023, 10, 27, 10, 0, 0)
    for i in range(100):
        t = start1 + timedelta(seconds=i*5)
        f.write(f"[{t.strftime('%Y-%m-%d %H:%M:%S')}] 192.168.1.10 GET /api/status 200\n")

    start2 = datetime(2023, 10, 27, 10, 10, 0)
    entries = []
    for i in range(142):
        entries.append("10.0.45.22 POST /api/upload 500")
    for i in range(15):
        entries.append("192.168.1.11 GET /api/data 200")

    random.seed(42)
    random.shuffle(entries)

    for i, entry in enumerate(entries):
        t = start2 + timedelta(seconds=i*1.5) # keep within 5 mins
        f.write(f"[{t.strftime('%Y-%m-%d %H:%M:%S')}] {entry}\n")
EOF

    python3 /tmp/gen_logs.py
    rm /tmp/gen_logs.py

    chmod -R 777 /home/user
