#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Install Rust for all users
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Make rust available to user
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup

    cat << 'EOF' > /home/user/sensor_logs.txt
Log entry 1: Temp is 45.2 C
Sensor-2 reading: 47.5 degrees
Error reading sensor, value N/A
Log entry 4: 46.1
Warning: Overheating at 44.8 C detected
[DEBUG] temp_val= 45.9
Sensor-1 failed
Reading 8: 48.0 C
Status: OK, temp 43.5
Log entry 10: 46.8
Measurement: 47.2
Final reading before shutdown: 45.5
EOF

    chmod -R 777 /home/user
