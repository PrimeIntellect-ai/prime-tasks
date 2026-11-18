#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset/gcode
    mkdir -p /home/user/dataset/corrected

    cat << 'EOF' > /home/user/dataset/machine_events.log
[EVENT START]
Timestamp: 2023-10-24T10:00:00
PrintID: P001
Level: INFO
Module: Extruder
Details: Normal operation
[EVENT END]
[EVENT START]
Timestamp: 2023-10-24T10:15:00
PrintID: P002
Level: ERROR
Module: Extruder
Details: Thermal runaway detected
[EVENT END]
[EVENT START]
Timestamp: 2023-10-24T10:30:00
PrintID: P003
Level: ERROR
Module: Bed
Details: Heating failed
[EVENT END]
[EVENT START]
Timestamp: 2023-10-24T10:45:00
PrintID: P004
Level: ERROR
Module: Extruder
Details: Jam detected
[EVENT END]
[EVENT START]
Timestamp: 2023-10-24T11:00:00
PrintID: P005
Level: INFO
Module: Extruder
Details: Print finished
[EVENT END]
EOF

    cat << 'EOF' > /home/user/dataset/gcode/P001.gcode
T0
G1 X10 Y10 Z0.2
G1 X20 Y10 Z0.4
T1
G1 X20 Y20 Z0.6
EOF

    cat << 'EOF' > /home/user/dataset/gcode/P002.gcode
T0
G1 X0 Y0 Z1.0
G1 X10 Y0
G1 X10 Y10 Z1.5
T1
G1 X20 Y20 Z2.0
T0
G1 X0 Y0 Z2.5
EOF

    cat << 'EOF' > /home/user/dataset/gcode/P003.gcode
T0
G1 X5 Y5 Z0.5
T1
G1 X10 Y10 Z1.0
EOF

    cat << 'EOF' > /home/user/dataset/gcode/P004.gcode
T1
G1 X1 Y1 Z0.1
T0
G1 X2 Y2 Z0.2
G1 X3 Y3
G1 X4 Y4 Z0.4
EOF

    cat << 'EOF' > /home/user/dataset/gcode/P005.gcode
T0
G1 X1 Y1 Z1.0
EOF

    chmod -R 777 /home/user
