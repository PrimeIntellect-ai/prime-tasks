#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app/telemetry_corpus/clean/
    mkdir -p /app/telemetry_corpus/evil/

    ffmpeg -f lavfi -i color=c=green:s=640x480:r=30:d=5 -f lavfi -i color=c=red:s=640x480:r=30:d=0.2 -f lavfi -i color=c=green:s=640x480:r=30:d=4.8 -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1:a=0[outv]" -map "[outv]" /app/uptime_feed.mp4

    cat << 'EOF' > /app/telemetry_corpus/clean/clean1.log
[1] 100 | 2.4:3.1 | 6
[2] 110 | 2.9:3.9 | 18
[3] 120 | -1.5:4.0 | 25
EOF

    cat << 'EOF' > /app/telemetry_corpus/evil/evil_sequence.log
[1] 100 | 2.4:3.1 | 6
[3] 110 | 2.9:3.9 | 19
EOF

    cat << 'EOF' > /app/telemetry_corpus/evil/evil_math.log
[1] 120 | -1.5:4.0 | 26
EOF

    cat << 'EOF' > /app/telemetry_corpus/evil/evil_format.log
[1] 100  2.4:3.1 | 6
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
