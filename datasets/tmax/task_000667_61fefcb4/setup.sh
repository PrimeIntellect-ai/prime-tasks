#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ingestion_system/logs
    mkdir -p /home/user/ingestion_system/raw_data

    # Create processor script
    cat << 'EOF' > /home/user/ingestion_system/process.sh
#!/bin/bash
PAYLOAD=$1
DURATION=$(echo "$PAYLOAD" | grep -o '"duration":[0-9\-]*' | cut -d':' -f2)
if [[ "$DURATION" -lt 0 ]]; then
    >&2 echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: Panic: unwrap() failed on negative metric"
    exit 134
fi
echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: Processed successfully"
exit 0
EOF
    chmod +x /home/user/ingestion_system/process.sh

    # Generate logs and raw data
    cat << 'EOF' > /tmp/generate_data.py
import json
import random
from datetime import datetime, timedelta

start_time = datetime(2023, 10, 1, 10, 0, 0)
service_a = open("/home/user/ingestion_system/logs/service_a.log", "w")
processor = open("/home/user/ingestion_system/logs/processor.log", "w")
raw_data = open("/home/user/ingestion_system/raw_data/dump_20231001.jsonl", "w")

crash_reqs = []

for i in range(1, 501):
    current_time = start_time + timedelta(seconds=i*15)
    req_id = f"req-{10000+i}"

    is_crash = False
    client_version = "1.2.0"
    duration = random.randint(10, 500)

    # Inject anomalies
    if i in [45, 122, 305, 410]:
        is_crash = True
        client_version = "1.0.4-beta"
        duration = random.randint(-50, -10)
        crash_reqs.append((current_time, req_id, client_version, duration))

    payload = {
        "req_id": req_id,
        "client_version": client_version,
        "metrics": {"duration": duration, "cpu": random.randint(10, 90)}
    }

    ts_str = current_time.strftime("%Y-%m-%d %H:%M:%S")
    service_a.write(f"[{ts_str}] INFO: Received incoming API request {req_id} from 192.168.1.{random.randint(10,200)}\n")

    proc_time = current_time + timedelta(seconds=2)
    proc_ts_str = proc_time.strftime("%Y-%m-%d %H:%M:%S")
    processor.write(f"[{proc_ts_str}] INFO: Starting processing for {req_id}\n")

    if is_crash:
        processor.write(f"[{proc_ts_str}] ERROR: Panic: unwrap() failed on negative metric. Traceback: main.rs:42\n")
    else:
        processor.write(f"[{proc_ts_str}] INFO: Completed processing for {req_id} successfully\n")

    raw_data.write(json.dumps(payload) + "\n")

service_a.close()
processor.close()
raw_data.close()
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chown -R user:user /home/user/ingestion_system
    chmod -R 777 /home/user
