#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset/batch1
    mkdir -p /home/user/dataset/batch2
    mkdir -p /home/user/dataset/batch3

    cat << 'EOF' > /home/user/dataset/batch1/item1.gcode
; Material: PETG
G1 X100.000 Y200.000 Z1.000
M104 S230
EOF

    cat << 'EOF' > /home/user/dataset/batch1/item2.gcode
; Material: PLA
G1 X100.000 Y200.000 Z1.000
M104 S210
EOF

    cat << 'EOF' > /home/user/dataset/batch2/item3.gcode
; Material: PETG
;;;; Custom header
G0 F3000
EOF

    cat << 'EOF' > /home/user/dataset/batch3/notes.txt
; Material: PETG
Some notes here...
EOF

    chmod -R 777 /home/user
