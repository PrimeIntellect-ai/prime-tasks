#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/doc_repo/gcodes

    cat << 'EOF' > /home/user/doc_repo/config.ini
[Models]
Benchy = gcodes/benchy.gcode
VoronPart = gcodes/voron_part.gcode
CalibCube = gcodes/calib_cube.gcode
EOF

    cat << 'EOF' > /home/user/doc_repo/gcodes/benchy.gcode
; FLAVOR:Marlin
; TIME:3600
; LAYER_COUNT:315
M104 S190
M109 S190
G28
M104 S215
G1 X10 Y10 Z0.2 F3000
M104 S210
EOF

    cat << 'EOF' > /home/user/doc_repo/gcodes/voron_part.gcode
; FLAVOR:Klipper
; LAYER_COUNT:150
M104 S240
M109 S240
G28
M104 S255
G1 X20 Y20 Z0.2
M104 S250
EOF

    cat << 'EOF' > /home/user/doc_repo/gcodes/calib_cube.gcode
; FLAVOR:Marlin
; LAYER_COUNT:50
M104 S200
M109 S200
G28
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
