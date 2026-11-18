#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset/run_01
    mkdir -p /home/user/dataset/run_02

    # Generate GCODE
    cat << 'EOF' > /home/user/dataset/run_01/motion.gcode
G21
G90
G0 X0 Y0 Z0
G1 X10 Y15.5 Z12.4 F1000
G1 X20 Y20 Z18.0
G1 X0 Y0 Z5.0
EOF

    cat << 'EOF' > /home/user/dataset/run_02/motion.gcode
G21
G90
G0 Z-1.5
G1 X5 Y5 Z2.2
G1 X10 Y10 Z10.1
EOF

    # Generate ELF (compile a simple dummy C program)
    cat << 'EOF' > /tmp/dummy1.c
int main() { return 0; }
EOF
    cat << 'EOF' > /tmp/dummy2.c
void _start() {}
EOF

    gcc -o /home/user/dataset/run_01/firmware.elf /tmp/dummy1.c
    gcc -nostdlib -o /home/user/dataset/run_02/firmware.elf /tmp/dummy2.c

    # Generate WAL files
    python3 -c "
import struct
with open('/home/user/dataset/run_01/sensor.wal', 'wb') as f:
    header = struct.pack('>IIIIIIII', 0x377f0682, 3007000, 4096, 1, 0, 0, 0, 0)
    f.write(header)
    f.write(b'\x00' * (12392 - 32))

with open('/home/user/dataset/run_02/sensor.wal', 'wb') as f:
    header = struct.pack('>IIIIIIII', 0x377f0682, 3007000, 1024, 1, 0, 0, 0, 0)
    f.write(header)
    f.write(b'\x00' * (5272 - 32))
"

    chown -R user:user /home/user/dataset
    chmod -R 777 /home/user
