#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gzip tar coreutils
    pip3 install pytest

    mkdir -p /home/user/dataset_incoming
    mkdir -p /home/user/dataset_processed

    cd /home/user/dataset_incoming

    cat << 'EOF' > partA.gcode
G28
G1 X10 Y10 Z0.2 E1.5
G1 X20 Y10 Z0.2 E3.0
G1 X20 Y20 Z0.2 E4.5
G1 X10 Y20 Z0.2 E6.0
G1 X10 Y10 Z0.2 E7.8
EOF

    cat << 'EOF' > partB.gcode
G28
G1 F200 X0 Y0 E0.0
G1 F200 X50 Y50 E102.4
G1 F200 X50 Y0 E150.9
EOF

    cat << 'EOF' > partC.gcode
G28
G1 X1 Y1 E5.0
EOF

    gzip partA.gcode
    gzip partB.gcode
    gzip partC.gcode

    dd if=/dev/urandom of=partC.gcode.gz bs=1 count=10 seek=5 conv=notrunc

    tar -czf robotics_data.tar.gz partA.gcode.gz partB.gcode.gz partC.gcode.gz
    rm partA.gcode.gz partB.gcode.gz partC.gcode.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
