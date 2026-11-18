#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset

    cat << 'EOF' > /home/user/dataset/experiment.conf
# Experiment 42 config
OPERATOR=Alice
Z_MIN=1.5
Z_MAX=3.0
MATERIAL=BioGel_A
EOF

    cat << 'EOF' > /home/user/dataset/print_run.gcode
; Start of print
G28 ; Home
G0 Z0.5 F1000 ; Move to initial height
G1 X10 Y10 E0.1 ; Extrude at Z=0.5
G1 X20 Y10 E0.2
G0 Z1.5 ; Move to Z=1.5 (boundary MIN)
G1 X20 Y20 E0.3 ; Should be captured
G1 X10 Y20 E0.4 ; Should be captured
G0 X0 Y0 Z2.5 ; Move X, Y, and Z
G1 X5 Y5 E0.5 ; Should be captured (Z=2.5)
G1 X5 Y5 ; No E parameter, skip
G0 Z3.1 ; Move to Z=3.1 (outside bounds)
G1 X10 Y10 E0.6 ; Should NOT be captured
G0 Z3.0 ; Move back to boundary MAX
G1 X15 Y15 E0.7 ; Should be captured
G0 Z5.0
G1 X0 Y0 E1.0 ; Skip
EOF

    chown -R user:user /home/user/dataset
    chmod -R 777 /home/user
