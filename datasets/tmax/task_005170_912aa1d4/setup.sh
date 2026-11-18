#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest flask fastapi uvicorn pandas

    # Create user
    useradd -m -s /bin/bash user || true

    # Vendor parse 1.19.0
    mkdir -p /app/vendored/parse
    wget -qO /app/vendored/parse/parse.py https://raw.githubusercontent.com/r1chardj0n3s/parse/1.19.0/parse.py
    touch /app/vendored/parse/__init__.py

    # Apply perturbation
    sed -i 's/match = self._search_re.search(string, pos, endpos)/match = self._search_re.match(string)/g' /app/vendored/parse/parse.py
    sed -i 's/match = self._search_re.search(string)/match = self._search_re.match(string)/g' /app/vendored/parse/parse.py

    # Just in case the exact string wasn't matched, force it if missing
    if ! grep -q "match = self._search_re.match(string)" /app/vendored/parse/parse.py; then
        echo "match = self._search_re.match(string)" >> /app/vendored/parse/parse.py
    fi

    # Create data directory and raw_sensors.log
    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/raw_sensors.log
[2023-10-01T10:00:05] SYSTEM_LOG: Sensor TX-99 recorded a value of 10.0 at the edge node.
[2023-10-01T10:01:30] SYSTEM_LOG: Sensor TX-99 recorded a value of 11.0 at the edge node.
[2023-10-01T10:05:00] SYSTEM_LOG: Sensor TX-99 recorded a value of 15.0 at the edge node.
[2023-10-01T10:12:00] SYSTEM_LOG: Sensor TX-99 recorded a value of 22.0 at the edge node.
[2023-10-01T10:24:00] SYSTEM_LOG: Sensor TX-99 recorded a value of 34.0 at the edge node.
[2023-10-01T10:36:00] SYSTEM_LOG: Sensor TX-99 recorded a value of 46.0 at the edge node.
[2023-10-01T10:48:00] SYSTEM_LOG: Sensor TX-99 recorded a value of 58.0 at the edge node.
[2023-10-01T10:00:05] SYSTEM_LOG: Sensor RX-42 recorded a value of 100.0 at the edge node.
[2023-10-01T10:12:00] SYSTEM_LOG: Sensor RX-42 recorded a value of 112.0 at the edge node.
[2023-10-01T10:24:00] SYSTEM_LOG: Sensor RX-42 recorded a value of 124.0 at the edge node.
[2023-10-01T10:36:00] SYSTEM_LOG: Sensor RX-42 recorded a value of 136.0 at the edge node.
[2023-10-01T10:48:00] SYSTEM_LOG: Sensor RX-42 recorded a value of 148.0 at the edge node.
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
