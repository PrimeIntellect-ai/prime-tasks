#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy

mkdir -p /var/log/monitoring
mkdir -p /app/bash-uptime-monitor-1.2.0
mkdir -p /opt/truth

cat << 'EOF' > /app/bash-uptime-monitor-1.2.0/recover.sh
#!/bin/bash
while IFS= read -r line || [ -n "$line" ]; do
    if [[ $line =~ ^([0-9]{4}-[0-9]{2}-[0-2][0-9]T[0-9]{2}:[0-9]{2}:[0-9]{2})\ (server-[0-9]+)\ (UP|DOWN)$ ]]; then
        echo "${BASH_REMATCH[1]},${BASH_REMATCH[2]},${BASH_REMATCH[3]}"
    fi
done < "$1"
EOF
chmod +x /app/bash-uptime-monitor-1.2.0/recover.sh

cat << 'EOF' > /tmp/generate_data.py
import random
from datetime import datetime, timedelta

servers = [f"server-{i}" for i in range(1, 51)]
start_time = datetime(2023, 10, 1)
end_time = datetime(2023, 10, 31, 23, 59, 59)
total_seconds = (end_time - start_time).total_seconds()

wal_lines = []
truth = {}

random.seed(42)

for server in servers:
    current_time = start_time
    state = "UP"
    up_time = 0

    while current_time < end_time:
        duration = random.randint(3600, 86400)
        next_time = current_time + timedelta(seconds=duration)
        if next_time > end_time:
            next_time = end_time
            duration = (next_time - current_time).total_seconds()

        wal_lines.append((current_time, server, state))

        if state == "UP":
            up_time += duration
            state = "DOWN"
        else:
            state = "UP"

        current_time = next_time

    truth[server] = (up_time / total_seconds) * 100.0

wal_lines.sort(key=lambda x: x[0])

with open('/var/log/monitoring/uptime.wal', 'w') as f:
    for t, s, st in wal_lines:
        f.write(f"{t.strftime('%Y-%m-%dT%H:%M:%S')} {s} {st}\n")

with open('/opt/truth/truth_uptime.csv', 'w') as f:
    for s, pct in truth.items():
        f.write(f"{s},{pct:.6f}\n")
EOF

python3 /tmp/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
