#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make coreutils tar gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/gcode_current

    cat << 'EOF' > /home/user/gcode_current/partA.gcode
;; VERSION: 1.0
G90
G21
M104 S200
EOF

    cat << 'EOF' > /home/user/gcode_current/partB.gcode
;; VERSION: 1.2
G90
G21
M104 S215
EOF

    cat << 'EOF' > /home/user/gcode_current/partC.gcode
;; VERSION: 2.0
G90
G21
M140 S60
EOF

    SHA_A=$(sha256sum /home/user/gcode_current/partA.gcode | awk '{print $1}')
    SHA_B_OLD="dummy_old_checksum_1234567890abcdef"

    cat << EOF > /home/user/manifest_v1.txt
partA.gcode,1.0,$SHA_A
partB.gcode,1.1,$SHA_B_OLD
EOF

    chmod -R 777 /home/user
