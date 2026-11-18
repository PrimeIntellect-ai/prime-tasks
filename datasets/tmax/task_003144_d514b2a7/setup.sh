#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tree
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_gcode
    mkdir -p /home/user/docs

    cat << 'EOF' > /home/user/raw_gcode/bracket.gcode
; FLAVOR:Marlin
; TIME:3600
; PRINTER: Ender3
; MATERIAL: PLA
G90
M82
M106 S0
EOF

    cat << 'EOF' > /home/user/raw_gcode/gear.gcode
; FLAVOR:Marlin
; PRINTER: PrusaMK3
; MATERIAL: PETG
; MINX:20
G90
M82
EOF

    cat << 'EOF' > /home/user/raw_gcode/flex_joint.gcode
; FLAVOR:Marlin
; PRINTER: Ender3
; MATERIAL: TPU
G90
EOF

    cat << 'EOF' > /home/user/raw_gcode/test_cube.gcode
; FLAVOR:Marlin
; TIME:1200
; test file
G90
EOF

    chown -R user:user /home/user/raw_gcode
    chown -R user:user /home/user/docs

    chmod -R 777 /home/user
