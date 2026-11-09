#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils tar
    pip3 install pytest

    mkdir -p /home/user/artifacts

    # 1. Create dummy ELF file
    cat << 'EOF' > /home/user/artifacts/dummy.c
int main() { return 0; }
EOF
    gcc /home/user/artifacts/dummy.c -o /home/user/artifacts/firmware.elf
    rm /home/user/artifacts/dummy.c

    # 2. Create GCode file
    cat << 'EOF' > /home/user/artifacts/jig_path.gcode
G28
G1 X10 Y10 Z5.0
G1 X20 Y20 Z12.4
G1 X30 Y30 Z8.1
G1 X0 Y0 Z24.5
G1 X10 Y10 Z24.5
EOF

    # 3. Create compressed log file
    mkdir -p /tmp/log_build
    cat << 'EOF' > /tmp/log_build/syslog.txt
Starting build...
Compiling dummy.c
--- BEGIN FATAL ---
Memory layout corrupted.
Address bus assertion failed.
Aborting build.
--- END FATAL ---
Cleaning up...
EOF
    tar -czf /home/user/artifacts/build_logs.tar.gz -C /tmp/log_build syslog.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
