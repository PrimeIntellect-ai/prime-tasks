#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/generate_logs.py
import datetime
import random
import time

random.seed(42)

base_time_utc = datetime.datetime(2023, 10, 25, 14, 0, 0, tzinfo=datetime.timezone.utc)

gateway_log = open("/home/user/logs/api_gateway.log", "w")
auth_log = open("/home/user/logs/auth_service.log", "w")
payment_log = open("/home/user/logs/payment_backend.log", "w")

failed_requests = []

for i in range(1, 501):
    req_id = f"REQ-{i:03d}"

    # Add random offset up to 2 hours
    offset = datetime.timedelta(seconds=random.randint(0, 7200))
    req_time_utc = base_time_utc + offset

    # Decide if this request fails
    # Make REQ-042, REQ-188, REQ-305, REQ-499 fail
    is_failure = i in [42, 188, 305, 499]

    # Auth log (Epoch)
    auth_time = req_time_utc.timestamp()
    auth_log.write(f"{auth_time:.3f} - tx_id:{req_id} - Authenticated successfully\n")

    # Payment log (EDT / UTC-4)
    pay_time_edt = req_time_utc - datetime.timedelta(hours=4)
    pay_time_str = pay_time_edt.strftime("%Y/%m/%d %H:%M:%S")

    retry_count = random.randint(0, 1)
    if is_failure:
        retry_count = random.randint(3, 5)
        failed_requests.append(req_id)

    payment_log.write(f"{pay_time_str} | trace={req_id} | STATE: retry_count={retry_count} | Payment {'failed' if is_failure else 'processed'}\n")

    # Gateway log (UTC ISO)
    gateway_time_str = req_time_utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    status = 503 if is_failure else 200
    gateway_log.write(f"[{gateway_time_str}] [req_id={req_id}] HTTP {status}\n")

gateway_log.close()
auth_log.close()
payment_log.close()
EOF

    python3 /home/user/generate_logs.py
    rm /home/user/generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
