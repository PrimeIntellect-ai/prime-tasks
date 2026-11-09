#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg jq zip tar bzip2 file coreutils
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/messy_project/sub1
    mkdir -p /home/user/messy_project/sub2
    mkdir -p /home/user/archives

    CONFIG="ELF:/home/user/archives/binaries.tar.gz
GCODE:/home/user/archives/manufacturing.zip
WAL:/home/user/archives/database_logs.tar.bz2"
    B64_CONFIG=$(echo "$CONFIG" | base64 -w 0)

    ffmpeg -f lavfi -i color=c=blue:s=320x240:d=1 -metadata comment="$B64_CONFIG" -c:v libx264 -y /app/project_screencast.mp4

    # Create ELFs
    printf "\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00" > /home/user/messy_project/sub1/random_file.txt
    printf "\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00" > /home/user/messy_project/sub2/exec.bin

    # Create WALs
    printf "\x37\x7f\x06\x82\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" > /home/user/messy_project/sub1/log.dat
    printf "\x37\x7f\x06\x83\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" > /home/user/messy_project/no_ext_file

    # Create GCODEs
    printf "M109 S200\nG1 X10 Y10\nM104 S0\n" > /home/user/messy_project/sub2/doc.pdf
    printf "M109 S210\nG0 X0 Y0\nG1 X20 Y20\n" > /home/user/messy_project/sub1/image.png

    # Create noise files
    printf "Just a normal text file\n" > /home/user/messy_project/sub1/real.txt
    printf "G1 X10 Y10\n" > /home/user/messy_project/sub2/fake_gcode.txt
    printf "M109 S200\n" > /home/user/messy_project/sub2/fake_gcode2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
