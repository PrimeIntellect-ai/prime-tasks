#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang binutils
pip3 install pytest

mkdir -p /home/user/data
mkdir -p /home/user/parser
mkdir -p /home/user/latest_configs

# Copy a real ELF file to use as the firmware
cp /bin/ls /home/user/data/firmware_v2.elf

# Create a GCode file in UTF-8, then convert to ISO-8859-1
cat << 'EOF' > /home/user/data/part_v2.gcode.utf8
G21 ; Set units to millimeters
G90 ; Absolute positioning
G0 X0 Y0 Z0
G1 X10 Y10 Z2.5 F1000
G1 X20 Y20 Z15.2
G0 X0 Y0 Z30.0
M104 S0 ; Turn off extruder
EOF
iconv -f UTF-8 -t ISO-8859-1 /home/user/data/part_v2.gcode.utf8 > /home/user/data/part_v2.gcode
rm /home/user/data/part_v2.gcode.utf8

# Create the WAL file
cat << 'EOF' > /home/user/data/sync.wal
PENDING 2023-10-01T12:00:00Z /home/user/data/firmware_v1.elf
COMMIT 2023-10-01T12:05:00Z /home/user/data/firmware_v2.elf
REJECT 2023-10-01T12:10:00Z /home/user/data/part_v1.gcode
COMMIT 2023-10-01T12:15:00Z /home/user/data/part_v2.gcode
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
