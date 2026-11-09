#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq bc gawk
pip3 install pytest

mkdir -p /home/user
cat << 'EOF' > /home/user/flight_data.log
[2023-11-01 10:15:22] INFO Drone ID: D-101 | Status: OK | Pos: 45.6000, -122.5000 | Payload: 2.5kg
[2023-11-01 10:16:00] ERROR Drone ID: D-102 | Status: OFFLINE | Connection Lost
[2023-11-01 10:17:10] INFO Drone ID: D-103 | Status: OK | Pos: 45.5500, -122.6500 | Payload: 1.0kg
[2023-11-01 10:18:05] WARNING Drone ID: D-104 | Status: LOW_BATTERY | Pos: 45.5200, -122.5900 | Payload: 1.5kg
[2023-11-01 10:19:33] INFO Drone ID: D-105 | Status: OK | Pos: 45.5100, -122.5800 | Payload: 3.2kg
[2023-11-01 10:20:00] ERROR Drone ID: D-106 | Status: CRASH | Pos: 45.5000, -122.6000 | Payload: 0.0kg
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
