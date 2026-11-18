#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/extracted /home/user/organized/calibration /home/user/organized/production

    cat << 'EOF' > /home/user/dataset.archive
[FILE_START]
test1.gcode
[CONTENT_START]
G21 ; Set units to millimeters
G90 ; Use absolute coordinates
G28 ; Home all axes
G1 Z5 F5000
[FILE_END]
[FILE_START]
subdir/test2.gcode
[CONTENT_START]
G21 ; Set units to millimeters
G90 ; Use absolute coordinates
G1 X10 Y20 F3000
G1 X10 Y30
[FILE_END]
[FILE_START]
../hacked.txt
[CONTENT_START]
This is a malicious file that should be skipped.
[FILE_END]
[FILE_START]
data/test3.gcode
[CONTENT_START]
G28 X Y ; Home X and Y
G1 Z10
[FILE_END]
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
