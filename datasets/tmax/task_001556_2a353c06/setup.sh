#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/processor.py
import json
import sys

def process_logs(file_path):
    temps = []
    processed_count = 0
    with open(file_path, 'r') as f:
        for line in f:
            if not line.strip(): continue
            data = json.loads(line)
            temp = float(data['temperature'])
            temps.append(temp)
            if len(temps) > 5:
                temps.pop(0)

            if len(temps) == 5:
                avg_temp = sum(temps) / 5
                if avg_temp > 100:
                    # High temperature compensation logic triggers
                    humidity = int(data['humidity']) # Crashes if humidity is "N/A"
                    pass # further processing

            processed_count += 1
    return processed_count

if __name__ == '__main__':
    try:
        process_logs(sys.argv[1])
        print("Success")
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
EOF

    cat << 'EOF' > /home/user/sensor_logs.ndjson
{"temperature": 45.0, "humidity": "40"}
{"temperature": 50.0, "humidity": "45"}
{"temperature": 55.0, "humidity": "50"}
{"temperature": 60.0, "humidity": "55"}
{"temperature": 65.0, "humidity": "60"}
{"temperature": 105.0, "humidity": "10"}
{"temperature": 110.0, "humidity": "15"}
{"temperature": 102.0, "humidity": "12"}
{"temperature": 108.0, "humidity": "14"}
{"temperature": 101.0, "humidity": "N/A"}
{"temperature": 40.0, "humidity": "30"}
EOF

    chmod -R 777 /home/user
