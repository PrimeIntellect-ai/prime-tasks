#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc e2fsprogs
    pip3 install pytest

    mkdir -p /app/dataset /app/frames /app/restored /tmp/setup

    # 1. Create the Video Fixture
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=1 \
           -vf "drawtext=text='%{pts\:hms}':x=10:y=10:fontsize=24:fontcolor=white" \
           -c:v libx264 -y /app/recording.mp4

    # 2. Create the GCode versions
    cat << 'EOF' > /tmp/setup/job_v1.gcode
G21 ; Set units to millimeters
G90 ; Absolute positioning
G1 X10 Y10 F1000
; SYNC T=00:00:02 Z=1.0
G1 Z1.0
G1 X20 Y20
; SYNC T=00:00:04 Z=2.0
G1 Z2.0
EOF

    # 3. Create incremental tarballs
    cd /tmp/setup
    mv job_v1.gcode job.gcode
    tar -cf base.tar job.gcode

    # overwrite with v2
    cat << 'EOF' > /tmp/setup/job.gcode
G21 ; Set units to millimeters
G90 ; Absolute positioning
G1 X10 Y10 F1000
; SYNC T=00:00:02 Z=1.0
G1 Z1.0
G1 X20 Y20
; SYNC T=00:00:04 Z=2.0
G1 Z2.0
G1 X30 Y30
; SYNC T=00:00:07 Z=3.5
G1 Z3.5
EOF
    tar -cf update.tar job.gcode

    # 4. Create filesystem image using mke2fs -d to avoid needing mount
    mkdir -p /tmp/mnt
    cp /tmp/setup/base.tar /tmp/mnt/
    cp /tmp/setup/update.tar /tmp/mnt/

    dd if=/dev/zero of=/app/cnc_data.ext4 bs=1M count=16
    mke2fs -t ext4 -d /tmp/mnt /app/cnc_data.ext4

    rm -rf /tmp/setup /tmp/mnt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
