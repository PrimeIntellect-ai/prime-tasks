#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/project_files/cnc_run1
    mkdir -p /home/user/project_files/firmware

    cat << 'EOF' > /tmp/part1.txt
; Start of part1
G21 ; Set units to millimeters
G90 ; Absolute positioning
G0 X10 Y10 Z5 F1000 °C
G1 X15 Y15 Z0 F500
G1 X20 Y15 Z0
G1 X20 Y20 Z0
M2 ; End
EOF
    iconv -f UTF-8 -t ISO-8859-1 /tmp/part1.txt > /home/user/project_files/cnc_run1/part1.gcode

    cat << 'EOF' > /tmp/part2.txt
; Start of part2
G0 Z10
G0 X0 Y0
G1 Z-1 F100
G1 X50 Y50 F800
G0 Z10
EOF
    iconv -f UTF-8 -t ISO-8859-1 /tmp/part2.txt > /home/user/project_files/cnc_run1/part2.gcode

    cat << 'EOF' > /tmp/fw1.c
int main() { return 0; }
EOF
    cat << 'EOF' > /tmp/fw2.c
void _start() { }
EOF

    gcc /tmp/fw1.c -o /home/user/project_files/firmware/fw1.elf
    gcc -nostdlib /tmp/fw2.c -o /home/user/project_files/firmware/fw2.elf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
