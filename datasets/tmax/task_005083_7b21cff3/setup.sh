#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3
    pip3 install pytest opencv-python-headless pandas numpy

    # Create directories
    mkdir -p /app/data
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate a dummy video
    ffmpeg -y -f lavfi -i testsrc=duration=2:size=640x480:rate=30 -pix_fmt yuv420p /app/data/dashboard.mp4

    # Generate clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.csv
frame_index,intensity
0,10.5
1,20.0
2,255.0
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.csv
frame_index,intensity
0,0.0
1,128.5
2,255.0
EOF

    # Generate evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1.csv
frame_index,intensity
0,10.5
2,20.0
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.csv
frame_index,intensity
0,10.5
1,256.0
EOF

    cat << 'EOF' > /app/corpus/evil/evil3.csv
frame_index,intensity
0,10.5
1,-1.0
EOF

    cat << 'EOF' > /app/corpus/evil/evil4.csv
frame_index,intensity
0,10.5
1,abc
EOF

    cat << 'EOF' > /app/corpus/evil/evil5.csv
frame_index,intensity
1,10.5
2,20.0
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
