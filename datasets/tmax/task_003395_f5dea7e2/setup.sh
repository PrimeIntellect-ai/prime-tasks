#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev findutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/datasets/gcode_logs/

    cat << 'EOF' > /home/user/datasets/gcode_logs/log1.gcode
G28
G1 X1.0 Y2.0 Z0.5
G1 E1.0
G1 X3.0 Y4.0
M104 S200
EOF

    cat << 'EOF' > /home/user/datasets/gcode_logs/log2.gcode
G1 X-1.5 Y10.0
G0 X0 Y0
G1 X5.0 Y-2.5
G1 X10.0 E3.0
G1 Y10.0 E4.0
EOF

    cat << 'EOF' > /home/user/datasets/gcode_logs/log3.gcode
G1 X100.5 Y200.5 E5.0
G1 X101.0 Y201.0 E5.1
M109 R190
EOF

    chmod -R 777 /home/user
