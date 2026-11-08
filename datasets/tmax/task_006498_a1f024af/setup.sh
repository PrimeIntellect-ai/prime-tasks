#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/raw_gcode
    mkdir -p /home/user/processed_gcode
    mkdir -p /home/user/backup

    cat << 'EOF' > /home/user/config.ini
[Storage]
source_dir = /home/user/raw_gcode
dest_dir = /home/user/processed_gcode
backup_dir = /home/user/backup
lines_per_chunk = 50
EOF

    cat << 'EOF' > /home/user/raw_gcode/printA.gcode
; Start GCode
M104 S200 ; Set nozzle temp
M140 S60 ; Set bed temp
G28 ; Home all axes
G1 Z5.0 F3000 ; Move Z up
EOF

    for i in $(seq 1 106); do
        echo "G1 X$i Y$i E0.1 ; inline comment $i" >> /home/user/raw_gcode/printA.gcode
    done

    cat << 'EOF' > /home/user/raw_gcode/printB.gcode
; Another file
; with a lot of
; comment lines

EOF

    for i in $(seq 1 40); do
        echo "G0 Z$i" >> /home/user/raw_gcode/printB.gcode
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
