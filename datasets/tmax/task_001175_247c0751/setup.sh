#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install --default-timeout=100 pytest

    mkdir -p /app

    cat << 'EOF' > /app/initial_config.json
{
  "maintenance_mode": false,
  "max_workers": 10,
  "target_region": "us-east-1",
  "log_level": "INFO",
  "retry_count": 3
}
EOF

    espeak -w /app/sysadmin_memo.wav "Update the configuration. Set the maintenance mode to true, max workers to 42, and target region to eu-west-1."

    python3 -c "
import random
from datetime import datetime, timedelta

status_codes = [200, 404, 500]
start_time = datetime(2023, 10, 1, 10, 0, 0)

with open('/app/server_logs.csv', 'w') as f:
    f.write('request_id,timestamp,status_code,response_time\n')
    for i in range(1, 1500):
        t = start_time + timedelta(seconds=i)
        sc = random.choice(status_codes)
        rt = random.randint(20, 2000)
        f.write(f'req_{i},{t.isoformat()}Z,{sc},{rt}\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
