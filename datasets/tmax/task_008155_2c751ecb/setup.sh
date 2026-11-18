#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tar gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/gcode_files
    mkdir -p /home/user/quick_prints

    cat << 'EOF' > /home/user/gcode_files/bench.gcode
; FLAVOR:Marlin
; TIME:1234
; LAYER_COUNT: 45
G1 X10 Y10
EOF

    cat << 'EOF' > /home/user/gcode_files/big_statue.gcode
; FLAVOR:Marlin
; TIME:9999
; LAYER_COUNT: 550
G1 X20 Y20
EOF

    cat << 'EOF' > /home/user/gcode_files/token.gcode
; FLAVOR:Marlin
; LAYER_COUNT: 12
G1 X5 Y5
EOF

    cat << 'EOF' > /home/user/gcode_files/edge_case.gcode
; FLAVOR:Marlin
; LAYER_COUNT: 50
G1 X5 Y5
EOF

    cat << 'EOF' > /home/user/gcode_files/almost.gcode
; FLAVOR:Marlin
; LAYER_COUNT: 49
G1 X5 Y5
EOF

    cat << 'EOF' > /home/user/gcode_files/invalid.txt
This is just a text file.
No layer count here.
EOF

    chown -R user:user /home/user/gcode_files
    chown -R user:user /home/user/quick_prints

    chmod -R 777 /home/user
