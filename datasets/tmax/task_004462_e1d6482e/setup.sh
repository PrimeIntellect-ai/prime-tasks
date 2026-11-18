#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/printing_dataset/batch_A/
    mkdir -p /home/user/printing_dataset/batch_B/nested/
    mkdir -p /home/user/printing_dataset/binaries/

    # Create symlink loops
    ln -s /home/user/printing_dataset/batch_A /home/user/printing_dataset/batch_A/loop_dir
    ln -s /home/user/printing_dataset /home/user/printing_dataset/batch_B/nested/root_loop

    # Create ELF files (dummies)
    echo -e "\x7fELF..." > /home/user/printing_dataset/binaries/test.elf

    # Create GCode files
    cat << 'EOF' > /home/user/printing_dataset/batch_A/cube.gcode
G28
G1 X10 Y10
; filament_used_mm: 12.4
G1 E12.4
EOF

    cat << 'EOF' > /home/user/printing_dataset/batch_A/sphere.gcode
G28
; filament_used_mm: 55.0
G1 Z5
EOF

    cat << 'EOF' > /home/user/printing_dataset/batch_B/nested/pyramid.gcode
G28
G1 X10 Y10
; some other comment
G1 E10
EOF

    cat << 'EOF' > /home/user/printing_dataset/batch_B/cylinder.gcode
; filament_used_mm: 98.12
M104 S200
EOF

    chmod -R 777 /home/user
