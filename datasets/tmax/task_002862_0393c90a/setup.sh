#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    cat << 'EOF' > /app/model_weights.txt
W_R=0.5
W_G=-0.2
W_B=0.1
W_speed=1.5
bias=-50
EOF

    echo "1,10,10,10,20,72" > /app/corpora/clean/data1.csv
    echo "2,20,20,20,25,73" > /app/corpora/clean/data2.csv

    echo "1,200,10,10,50,72" > /app/corpora/evil/data1.csv
    echo "2,250,20,20,60,73" > /app/corpora/evil/data2.csv

    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=1 -c:v libx264 /app/traffic.mp4 -y

    cat << 'EOF' > /app/telemetry.csv
1,15,70
2,16,70
3,14,71
4,55,71
5,15,70
6,16,70
7,15,71
8,14,71
9,15,72
10,16,72
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
