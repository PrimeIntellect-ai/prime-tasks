#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_telemetry.log
[LOG] t=0.0s | sensor_pwr=10.0W | status=idle
[LOG] t=0.5s | sensor_pwr=11.5W | status=idle
[LOG] t=1.0s | sensor_pwr=15.0W | status=idle
[LOG] t=1.5s | sensor_pwr=45.0W | status=active
[LOG] t=2.0s | sensor_pwr=80.0W | status=active
[LOG] t=2.5s | sensor_pwr=30.0W | status=cooldown
[LOG] t=3.0s | sensor_pwr=10.0W | status=idle
EOF

    chmod -R 777 /home/user
