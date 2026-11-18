#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user/docs_project
cd /home/user/docs_project

# Create dummy ELF files
echo -n "ELF1" > fw_v1.elf
echo -n "ELF222" > fw_v2.elf

# Create GCode file
cat << 'EOF' > model_v2.gcode
; FLAVOR:Marlin
; TIME:2100
G28 ; home all axes
G1 Z5 F5000 ; lift nozzle
; Layer 1
G1 X10 Y10 F3000
; TIME:320
G1 X20 Y20 F3000
; TIME:18
M104 S0
EOF

# Create index.md without using forbidden build variables
cat << 'EOF' > index.md
# Printer Model V2 Documentation

The total print time for the default calibration cube is P_T seconds.
Please ensure you flash the firmware using the file: L_F
EOF

# Replace placeholders with curly braces to avoid Apptainer parser errors
P1="{"
P2="{"
P3="}"
P4="}"
sed -i "s/P_T/${P1}${P2}PRINT_TIME${P3}${P4}/g" index.md
sed -i "s/L_F/${P1}${P2}LATEST_FIRMWARE${P3}${P4}/g" index.md

# Setup user and permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
