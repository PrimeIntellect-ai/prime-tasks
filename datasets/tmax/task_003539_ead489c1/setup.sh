#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/incoming_logs
mkdir -p /home/user/archive

cat << 'EOF' > /home/user/incoming_logs/day1.log
[2023-10-01T10:00:00] Route alpha-01: Departed from (X: 0.0, Y: 0.0) -> Arrived at (X: 3.0, Y: 4.0) | Status: SUCCESS
[2023-10-01T10:05:00] Route beta-02: Departed from (X: -1.5, Y: 2.5) -> Arrived at (X: 1.5, Y: 6.5) | Status: SUCCESS
[2023-10-01T10:10:00] Route gamma-03: Departed from (X: 10.0, Y: 10.0) -> Arrived at (X: 12.0, Y: 12.0) | Status: FAILED
[2023-10-01T10:15:00] Route delta-04: Departed from (X: 5.2, Y: -3.1) -> Arrived at (X: 5.2, Y: 8.9) | Status: SUCCESS
[2023-10-01T10:20:00] Invalid log entry without coordinates | Status: SUCCESS
EOF

chmod -R 777 /home/user
