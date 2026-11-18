#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/build.log.2
[RECORD_START] ID: 001
TYPE: GCODE
DATA:
G1 X10 Y10 Z2.5
G0 Z5.0
G1 X20
EOF

    cat << 'EOF' > /home/user/logs/build.log.1
G1 Z12.4
[RECORD_END]
[RECORD_START] ID: 002
TYPE: ELF
DATA:
Magic:   7f 45 4c 46 02 01 01 00
Class:                             ELF64
Entry point address:               0x8048100
Start of program headers:          64 (bytes into file)
[RECO
EOF

    cat << 'EOF' > /home/user/logs/build.log
RD_END]
[RECORD_START] ID: 003
TYPE: GCODE
DATA:
G0 Z1.1
G1 X50 Y50 Z-0.5
[RECORD_END]
EOF

    chmod -R 777 /home/user
