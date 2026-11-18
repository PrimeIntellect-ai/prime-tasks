#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zip unzip binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/setup_tmp
    cd /home/user/setup_tmp

    # 1. Create a dummy ELF file
    cat << 'EOF' > dummy.c
#include <stdio.h>
int main() {
    printf("Hello World\n");
    return 0;
}
EOF
    gcc dummy.c -o firmware.elf

    # 2. Create the multi-line log file
    cat << 'EOF' > compiler_output.log
---
[INFO] Starting build process...
[INFO] Compiling objects
---
[WARN] Implicit declaration of function 'do_something'
[INFO] Linking objects
---
[ERROR] Linker warnings detected
FATAL ERROR: Corrupted binary generated: /home/user/project_files/firmware.elf
Dump: 0x00 0x01 0x02
Stack trace line 1
Stack trace line 2
---
[INFO] Build finished with errors.
---
EOF

    # 3. Create the GCode file
    cat << 'EOF' > main_print.gcode
M104 S200
M140 S60
G28
G1 Z15.0 F6000
;LAYER_CHANGE
G1 X10 Y10 F3000
G1 X20 Y10 F3000
;LAYER_CHANGE
G1 X20 Y20 F3000
G1 X10 Y20 F3000
;LAYER_CHANGE
G1 X10 Y10 F3000
M104 S0
M140 S0
EOF

    # 4. Create a corrupt file to test archive integrity
    head -c 1024 /dev/urandom > corrupt_data.bin

    # 5. Zip them up
    zip /home/user/project_backup.zip firmware.elf compiler_output.log main_print.gcode corrupt_data.bin

    cd /home/user
    rm -rf /home/user/setup_tmp

    chmod -R 777 /home/user
