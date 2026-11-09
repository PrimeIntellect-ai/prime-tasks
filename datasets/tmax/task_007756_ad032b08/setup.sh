#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils tar gzip
    pip3 install pytest

    mkdir -p /home/user/archive

    cat << 'EOF' > /tmp/machine.gcode
G21
G90
M82
M107
G28 W
G1 Z0.200 F7800
G1 X10 Y10 E0.5
G1 X20 Y10 E1.0
G1 Z0.400 F7800
G1 X20 Y20 E1.5
G1 Z0.600 F7800
G1 X10 Y20 E2.0
G1 Z0.800 F7800
G1 X10 Y10 E2.5
G1 Z1.000 F7800
G1 Z1.200 F7800
EOF

    cd /tmp
    tar -czf - machine.gcode | split -a 1 -b 100 - /home/user/archive/data.tar.gz.part
    rm /tmp/machine.gcode

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
