#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        nginx redis-server redis-tools curl wget psmisc
    pip3 install pytest

    # Install Vector
    wget https://packages.timber.io/vector/0.33.0/vector-0.33.0-x86_64-unknown-linux-musl.tar.gz
    tar -xvf vector-0.33.0-x86_64-unknown-linux-musl.tar.gz
    cp vector-x86_64-unknown-linux-musl/bin/vector /usr/local/bin/
    rm -rf vector-0.33.0-x86_64-unknown-linux-musl*

    # Create directories
    mkdir -p /home/user/services/nginx
    mkdir -p /home/user/services/vector
    mkdir -p /home/user/services/logs
    mkdir -p /opt/oracle

    # Create oracle script
    cat << 'EOF' > /opt/oracle/log_transform_oracle.py
import sys
import json
from collections import defaultdict

def process_logs(file_path):
    users = defaultdict(list)
    with open(file_path, 'r') as f:
        for line in f:
            if not line.strip(): continue
            record = json.loads(line)
            users[record['user_id']].append(record)

    all_records = []
    for uid, records in users.items():
        records.sort(key=lambda x: x['timestamp'])
        for i, r in enumerate(records):
            latency = float(r['latency'])
            if i == 0:
                sma = latency
                diff = 0.0
            elif i == 1:
                sma = (float(records[0]['latency']) + latency) / 2
                diff = abs(latency - float(records[0]['latency']))
            else:
                sma = (float(records[i-2]['latency']) + float(records[i-1]['latency']) + latency) / 3
                diff = abs(latency - float(records[i-1]['latency']))

            all_records.append({
                'timestamp': r['timestamp'],
                'user_id': uid,
                'endpoint': r['endpoint'],
                'latency': latency,
                'rolling_avg_latency': sma,
                'latency_diff': diff
            })

    all_records.sort(key=lambda x: (x['timestamp'], x['user_id']))

    print("timestamp,user_id,endpoint,latency,rolling_avg_latency,latency_diff")
    for r in all_records:
        print(f"{r['timestamp']},{r['user_id']},{r['endpoint']},{r['latency']:.4f},{r['rolling_avg_latency']:.4f},{r['latency_diff']:.4f}")

if __name__ == '__main__':
    process_logs(sys.argv[1])
EOF

    # Initial broken config files
    cat << 'EOF' > /home/user/services/nginx/nginx.conf
worker_processes 1;
daemon off;
events {
    worker_connections 1024;
}
http {
    # TODO: Define json_log format
    server {
        listen 8080;
        location / {
            return 200 "OK\n";
        }
        # TODO: Configure access_log
    }
}
EOF

    cat << 'EOF' > /home/user/services/vector/vector.toml
# TODO: Configure source to tail access.log
# TODO: Configure transform to parse JSON
# TODO: Configure redis sink
EOF

    # Manage services script
    cat << 'EOF' > /home/user/manage_services.sh
#!/bin/bash
if [ "$1" == "restart" ] || [ "$1" == "start" ]; then
    killall nginx vector redis-server 2>/dev/null || true
    sleep 1
    redis-server --daemonize yes
    nginx -c /home/user/services/nginx/nginx.conf &
    vector --config /home/user/services/vector/vector.toml &
fi
if [ "$1" == "stop" ]; then
    killall nginx vector redis-server 2>/dev/null || true
fi
EOF
    chmod +x /home/user/manage_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
