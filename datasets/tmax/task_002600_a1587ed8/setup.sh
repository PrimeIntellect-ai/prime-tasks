#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Create directories
mkdir -p /home/user/cnc_docs/folder1/subfolder
mkdir -p /home/user/cnc_docs/folder2

# Create symlink loop
ln -s /home/user/cnc_docs/folder2 /home/user/cnc_docs/folder1/link_to_2
ln -s /home/user/cnc_docs/folder1 /home/user/cnc_docs/folder2/link_to_1

# Create GCode files with Windows-1252 encoding
cat << 'EOF' > /home/user/cnc_docs/folder1/part1.gcode.utf8
G21 ; Set units to millimeters
; Initialize spindlé
M03 S1000
G00 X0 Y0
; Cut at 45° angle
G01 X10 Y10 F100
EOF

cat << 'EOF' > /home/user/cnc_docs/folder2/part2.gcode.utf8
; Begin finishing pass
G02 X20 Y20 I10 J0
; End of job
M30
EOF

iconv -f UTF-8 -t WINDOWS-1252 /home/user/cnc_docs/folder1/part1.gcode.utf8 > /home/user/cnc_docs/folder1/part1.gcode
iconv -f UTF-8 -t WINDOWS-1252 /home/user/cnc_docs/folder2/part2.gcode.utf8 > /home/user/cnc_docs/folder2/part2.gcode
rm /home/user/cnc_docs/folder1/part1.gcode.utf8 /home/user/cnc_docs/folder2/part2.gcode.utf8

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
