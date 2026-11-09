#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ file tar
    pip3 install pytest

    mkdir -p /home/user/dropzone
    mkdir -p /home/user/archive_backup
    mkdir -p /tmp/v1 /tmp/v2

    # Create v1 contents
    cat << 'EOF' > /tmp/v1/main.cpp
int main() { return 0; }
EOF
    g++ /tmp/v1/main.cpp -o /tmp/v1/firmware.elf
    cat << 'EOF' > /tmp/v1/test.gcode
G28
G1 X10 Y10
; TIME: 4500s
M104 S0
EOF
    tar -czvf /home/user/dropzone/release_v1.tar.gz -C /tmp/v1 firmware.elf test.gcode

    # Create v2 contents
    cat << 'EOF' > /tmp/v2/util.cpp
int main() { return 1; }
EOF
    g++ /tmp/v2/util.cpp -o /tmp/v2/util.bin
    cat << 'EOF' > /tmp/v2/calib.gcode
; TIME: 120s
G28
EOF
    tar -czvf /home/user/dropzone/release_v2.tar.gz -C /tmp/v2 util.bin calib.gcode

    # Create corrupt archive
    head -c 100 /dev/urandom > /home/user/dropzone/broken_release.tar.gz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
