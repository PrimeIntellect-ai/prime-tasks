#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar
pip3 install pytest

mkdir -p /home/user/storage_pool/proj1
mkdir -p /home/user/storage_pool/proj2
mkdir -p /home/user/cleaned_gcode

# 1. Create valid GCode files
cat << 'EOF' > /home/user/storage_pool/proj1/print1.gcode
; Initial setup
G21 ; Set units to millimeters
G90 ; Use absolute coordinates
G1 X100 Y100 F1500 ; Move to center
M104 S200 ; Set extruder temp
EOF

cat << 'EOF' > /home/user/storage_pool/proj2/print2.gcode
; Part 2
M109 S200 ; Wait for temp
G1 Z0.2 F1200
    ; indented comment
G1 X110 Y110 E1.5
EOF

# 2. Create a valid tar archive
echo "dummy data" > /tmp/dummy.txt
tar -czf /home/user/storage_pool/proj1/backup1.tar.gz -C /tmp dummy.txt

# 3. Create a corrupt tar archive
echo "This is not a valid tar archive, it is just plain text" > /home/user/storage_pool/proj2/broken_backup.tar.gz

# 4. Create the symlink loop
ln -s /home/user/storage_pool/proj2 /home/user/storage_pool/proj2/link_loop

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
