#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file using espeak
    espeak -w /app/memo.wav "For the new ETL pipeline, every output line must be formatted exactly as follows: Data point, open square bracket, the sensor name, close square bracket, equals, the temperature formatted to exactly one decimal place, underscore, the timestamp."

    # Create the oracle script
    cat << 'EOF' > /app/oracle_etl.py
import sys
import json

def main():
    state = {}
    for line in sys.stdin:
        if not line.strip():
            continue
        data = json.loads(line)
        sensor = data["sensor"]
        temp = data["temp"]
        ts = data["ts"]
        status = data["status"]

        if temp is None:
            temp = state.get(sensor, 0.0)
        else:
            state[sensor] = temp

        print(f"Data point[{sensor}]={temp:.1f}_{ts} {status}")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
