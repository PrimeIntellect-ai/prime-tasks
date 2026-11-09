#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/dataset

    cat << 'EOF' > /home/user/dataset/config.txt
100.0
50.0
EOF

    cat << 'EOF' > /home/user/dataset/experiment_01_utf8.gcode
; Start of experiment
M104 S200
G28 ; Home all axes
G1 X10.5 Y20.0 F3000
G0 X15.0 Y25.5
M109 S200
G1 X20.0 Y30.0 E1.5
; End of layer
EOF

    iconv -f UTF-8 -t UTF-16LE /home/user/dataset/experiment_01_utf8.gcode > /home/user/dataset/experiment_01.gcode
    rm /home/user/dataset/experiment_01_utf8.gcode

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/dataset
    chmod -R 777 /home/user
