#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gzip util-linux file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/extracted
    mkdir -p /home/user/organized

    # Create a staging area for packing
    mkdir -p /tmp/stage/level1/level2

    # Create mock ELF files
    printf "\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00" > /tmp/stage/level1/program_a
    printf "\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00" > /tmp/stage/level1/level2/program_b
    printf "MZ\x90\x00\x03\x00\x00\x00" > /tmp/stage/level1/not_elf_program

    # Create mock GCode files
    cat << 'EOF' > /tmp/stage/level1/part1.gcode
; FLAVOR:Marlin
; TIME:3600
G28
G1 Z15.0 F6000
EOF

    cat << 'EOF' > /tmp/stage/level1/level2/part2_noext
; FLAVOR:Marlin
; Firmware version: 2.0
; TIME:8450
G28 X Y
EOF

    # Create a large log file
    cat << 'EOF' > /tmp/stage/level1/system.log
Log Started
EOF
    for i in {2..1200}; do
        echo "Log entry line $i" >> /tmp/stage/level1/system.log
    done

    # Create normal text files
    echo "Project Alpha Documentation" > /tmp/stage/level1/readme.txt
    echo "Changelog for V2" > /tmp/stage/level1/level2/changelog.md

    # Package the files into nested archives
    cd /tmp/stage/level1/level2
    tar -cf ../level2_archive.tar *
    rm -f *
    cd /tmp/stage/level1
    zip inner_archive.zip level2_archive.tar part1.gcode program_a
    rm -f level2_archive.tar part1.gcode program_a
    cd /tmp/stage
    tar -czf /home/user/incoming/legacy_dump.tar.gz -C level1 .
    rm -rf /tmp/stage

    chmod -R 777 /home/user
