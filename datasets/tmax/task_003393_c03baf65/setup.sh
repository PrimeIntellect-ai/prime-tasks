#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest pyelftools

    mkdir -p /home/user/gcode_parts
    mkdir -p /home/user/firmwares

    python3 -c "
with open('/home/user/gcode_parts/print.gcode.part1', 'w', encoding='utf-8') as f:
    f.write('G1 X10 Y10 E2.5\nG1 X20 Y20 E3.0\n')
with open('/home/user/gcode_parts/print.gcode.part2', 'w', encoding='utf-16le') as f:
    f.write('G1 X30 Y30 E1.5\nG1 X40 Y40 E4.5\n')
with open('/home/user/gcode_parts/print.gcode.part3', 'w', encoding='windows-1252') as f:
    f.write('G1 X50 Y50 E0.5\nM104 S200\n')
"

    cat << 'EOF' > /home/user/firmwares/v1.c
int main() { return 0; }
EOF

    cat << 'EOF' > /home/user/firmwares/v2.c
#include <stdio.h>
int main() { printf("Firmware V2\n"); return 0; }
EOF

    gcc /home/user/firmwares/v1.c -o /home/user/firmwares/v1.elf
    gcc /home/user/firmwares/v2.c -o /home/user/firmwares/v2.elf

    cat << 'EOF' > /home/user/config_manager.wal
[2023-10-01T10:00:00] | FIRMWARE_UPDATE | /home/user/firmwares/v1.elf | SUCCESS
[2023-10-01T14:30:00] | PRINT_START | /home/user/merged_print.gcode | SUCCESS
[2023-10-02T09:15:00] | FIRMWARE_UPDATE | /home/user/firmwares/v2.elf | SUCCESS
[2023-10-02T10:00:00] | FIRMWARE_UPDATE | /home/user/firmwares/v3_corrupted.elf | FAILED
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
