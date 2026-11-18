#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    apt-get install -y ffmpeg g++ make wget curl

    # Create directories
    mkdir -p /app

    # Create reads file
    cat << 'EOF' > /app/reads.txt
ACGTAAC
CGTAATC
TAACCGG
ACCGGTT
CGGTTAT
GTTACGC
TATGCAT
TGCATGC
EOF

    # Generate calibration video
    ffmpeg -f lavfi -i color=c=red:d=1 \
           -f lavfi -i color=c=green:d=1 \
           -f lavfi -i color=c=blue:d=1 \
           -f lavfi -i color=c=yellow:d=1 \
           -f lavfi -i color=c=red:d=1 \
           -f lavfi -i color=c=red:d=1 \
           -f lavfi -i color=c=green:d=1 \
           -f lavfi -i color=c=green:d=1 \
           -f lavfi -i color=c=blue:d=1 \
           -f lavfi -i color=c=blue:d=1 \
           -f lavfi -i color=c=yellow:d=1 \
           -f lavfi -i color=c=yellow:d=1 \
           -filter_complex "[0:v][1:v][2:v][3:v][4:v][5:v][6:v][7:v][8:v][9:v][10:v][11:v]concat=n=12:v=1:a=0[outv]" \
           -map "[outv]" -r 1 -y /app/calibration.mp4

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
