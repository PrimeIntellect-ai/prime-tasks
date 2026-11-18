#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    # Create the user first to ensure /home/user exists
    useradd -m -s /bin/bash user || true

    # Create the raw sensor logs file
    cat << 'EOF' > /home/user/raw_sensor_logs.txt
[2023-10-01 08:15:30] DEVICE_01 STATUS: OK TEMP: 22.0 HUM: 45
[2023-10-01 08:45:00] DEVICE_01 STATUS: OK TEMP: 24.0 HUM: 46
Some random unstructured log entry that should be ignored.
[2023-10-01 11:10:00] DEVICE_01 STATUS: OK TEMP: 25.0 HUM: 47
[2023-10-01 12:05:00] DEVICE_01 STATUS: OK TEMP: 26.0 HUM: 48
[2023-10-01 08:20:00] DEVICE_02 STATUS: WARN TEMP: 52.0 HUM: 40
[2023-10-01 08:00:00] DEVICE_03 STATUS: OK TEMP: 10.0 HUM: 50
[2023-10-02 08:00:00] DEVICE_03 STATUS: OK TEMP: 12.0 HUM: 50
EOF

    # Set permissions
    chmod -R 777 /home/user
