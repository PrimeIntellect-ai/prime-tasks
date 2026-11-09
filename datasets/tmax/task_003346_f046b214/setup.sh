#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang
    pip3 install pytest

    mkdir -p /app/video /app/corpus/clean /app/corpus/evil

    # Create a dummy video file using ffmpeg
    ffmpeg -f lavfi -i testsrc=duration=2:size=320x240:rate=10 -c:v libx264 /app/video/feed.mp4

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/data1.csv
0.1,1500
0.2,1600
0.3,1550
EOF

    cat << 'EOF' > /app/corpus/clean/data2.csv
1.0,200
2.0,300
3.0,400
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1_nan.csv
0.1,1500
0.2,NaN
0.3,1550
EOF

    cat << 'EOF' > /app/corpus/evil/evil2_inf.csv
0.1,1500
0.2,1600
0.3,+Inf
EOF

    cat << 'EOF' > /app/corpus/evil/evil3_neg.csv
0.1,1500
0.2,-500
0.3,1550
EOF

    cat << 'EOF' > /app/corpus/evil/evil4_str.csv
0.1,1500
0.2,invalid
0.3,1550
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
