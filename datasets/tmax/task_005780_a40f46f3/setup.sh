#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/project_data/cnc/parts
mkdir -p /home/user/project_data/firmware/v1
mkdir -p /home/user/project_data/firmware/v2

cat << 'EOF' > /home/user/project_data/cnc/parts/base.gcode
G0 X0 Y0
G1 X10 Y10 E1.5
G1 X20 Y10 E2.0
G0 X20 Y20
G1 X10 Y20 E1.25
EOF

cat << 'EOF' > /home/user/project_data/cnc/parts/gear.gcode
G0 X5 Y5
G1 X15 Y15 E3.4
G1 X15 Y20 E0.6
EOF

printf "\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00" > /home/user/project_data/firmware/v1/boot.elf
printf "\x02\x00\x3e\x00\x01\x00\x00\x00\x78\x56\x34\x12\x00\x00\x00\x00" >> /home/user/project_data/firmware/v1/boot.elf

printf "\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00" > /home/user/project_data/firmware/v2/main.elf
printf "\x02\x00\xb7\x00\x01\x00\x00\x00\x00\x00\x40\x00\x00\x00\x00\x00" >> /home/user/project_data/firmware/v2/main.elf

chmod -R 777 /home/user
