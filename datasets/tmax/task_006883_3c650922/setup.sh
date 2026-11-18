#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/gcode_files
    mkdir -p /home/user/archive/long_prints
    mkdir -p /home/user/archive/short_prints

    cat << 'EOF' > /home/user/gcode_files/part_A.gcode
G28
G1 X10 Y10 F3000
; estimated_time_s: 8000
G1 Z10
M104 S0
EOF

    cat << 'EOF' > /home/user/gcode_files/part_B.gcode
G28
G1 X20 Y20 F3000
; estimated_time_s: 3600
M104 S0
EOF

    cat << 'EOF' > /home/user/gcode_files/part_C.gcode
G28
; just some comments
G1 Z5
M104 S0
EOF

    cat << 'EOF' > /home/user/gcode_files/part_D.gcode
; estimated_time_s: 7200
G28
EOF

    cat << 'EOF' > /home/user/print_farm.conf
/home/user/gcode_files/part_A.gcode
/home/user/gcode_files/part_B.gcode
/home/user/gcode_files/part_C.gcode
/home/user/gcode_files/part_D.gcode
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
