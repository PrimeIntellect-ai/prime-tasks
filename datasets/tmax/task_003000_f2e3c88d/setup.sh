#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/sre_app /home/user/logs

    cat << 'EOF' > /home/user/sre_app/app.py
import time
import json

def generate_logs():
    base_time = 1700000000
    logs = [
        {"timestamp": base_time, "msg": "Service started"},
        {"timestamp": base_time + 10, "msg": "Ping OK"},
        {"timestamp": base_time + 20, "msg": "Ping OK"},
        {"timestamp": base_time + 90, "msg": "Ping OK"}, # 70s gap
        {"timestamp": base_time + 100, "msg": "Ping OK"}
    ]
    with open('/home/user/logs/app.log', 'w') as f:
        for log in logs:
            f.write(f"{log['timestamp']} - {log['msg']}\n")

if __name__ == "__main__":
    generate_logs()
EOF

    cat << 'EOF' > /home/user/sre_app/monitor.py
import json

def parse_logs(filepath):
    pings = []
    with open(filepath, 'r') as f:
        for line in f:
            if "Ping OK" in line:
                parts = line.strip().split(" - ")
                pings.append({"time": int(parts[0])})
    return pings

def check_gaps(pings):
    alerts = 0
    # BUG: off-by-one error here, should be range(len(pings) - 1)
    for i in range(len(pings)):
        gap = pings[i+1]['time'] - pings[i]['time']
        if gap > 60:
            alerts += 1
    return alerts

def main():
    with open('/home/user/logs/monitor.log', 'w') as f:
        f.write("1700000005 - Monitor started\n")
        f.write("1700000015 - Processed early pings\n")
        f.write("1700000105 - Crash imminent\n")

    pings = parse_logs('/home/user/logs/app.log')
    try:
        alerts = check_gaps(pings)
        print(f"Total alerts: {alerts}")
    except Exception as e:
        print(f"Error: {e}")
        raise

if __name__ == "__main__":
    main()
EOF

    python3 /home/user/sre_app/app.py
    python3 /home/user/sre_app/monitor.py > /dev/null 2>&1 || true

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
