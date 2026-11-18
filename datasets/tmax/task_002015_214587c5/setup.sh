#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq binutils zip unzip gcc tar gzip coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/backup_staging
cd /home/user/backup_staging

# 1. Create config.json
cat << 'EOF' > config.json
{
  "project": "Titan",
  "assets": [
    {"id": "A-101", "name": "Main Bracket"},
    {"id": "B-202", "name": "Drive Gear"},
    {"id": "C-303", "name": "Sensor Housing"}
  ]
}
EOF

# 2. Create GCode files
mkdir models
echo "; AssetID: A-101" > models/file1.gcode
echo "G0 X10 Y10 Z0" >> models/file1.gcode
echo "; AssetID: B-202" > models/file2.gcode
echo "G1 X20 Y20 Z10" >> models/file2.gcode
echo "; AssetID: C-303" > models/file3.gcode
echo "G28" >> models/file3.gcode
tar -cf models.tar -C models .
rm -rf models

# 3. Create mock ELF files
mkdir firmware
cat << 'EOF' > firmware/controller.c
int main() { return 0; }
EOF
cat << 'EOF' > firmware/sensor.c
int main() { return 1; }
EOF
gcc firmware/controller.c -o firmware/controller.elf
gcc firmware/sensor.c -o firmware/sensor.elf
rm firmware/*.c
cd firmware
zip ../firmware.zip *.elf
cd ..
rm -rf firmware

# 4. Create main tarball
tar -czf titan_raw.tar.gz config.json models.tar firmware.zip
rm config.json models.tar firmware.zip

chmod -R 777 /home/user
