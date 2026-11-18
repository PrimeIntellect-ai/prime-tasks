#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/uptime_data.json
{
  "statuses": ["UP", "DOWN", "DOWN", "UP", "UP", "UP", "DOWN", "DOWN", "DOWN", "DOWN"]
}
EOF

cat << 'EOF' > /home/user/monitor.py
import os
import json
import requests

def calculate_max_downtime(status_list):
    max_streak = 0
    current_streak = 0
    for status in status_list:
        if status == 'DOWN':
            current_streak += 1
        else:
            if current_streak > max_streak:
                max_streak = current_streak
            current_streak = 0
    # BUG: Fails to check if current_streak > max_streak at the end of the loop
    return max_streak

def main():
    data_path = os.environ.get('UPTIME_DATA_PATH')
    if not data_path:
        raise ValueError("Environment variable UPTIME_DATA_PATH not set. Please set it to the path of the uptime data JSON.")

    with open(data_path, 'r') as f:
        data = json.load(f)

    max_down = calculate_max_downtime(data['statuses'])

    with open('/home/user/report.json', 'w') as f:
        json.dump({"max_downtime_minutes": max_down}, f)

if __name__ == "__main__":
    main()
EOF

python3 -m venv /home/user/venv
/home/user/venv/bin/pip install "requests==2.31.0" "urllib3==1.25.0"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
