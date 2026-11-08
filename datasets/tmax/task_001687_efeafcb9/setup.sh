#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo
    pip3 install pytest

    # Create app directory and generate test video
    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -pix_fmt yuv420p /app/footage.mp4

    # Create data directory and CSV files
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/table_alpha.csv
event_id,timestamp_sec
1,2.5
2,5.1
3,8.0
EOF

    cat << 'EOF' > /home/user/data/table_beta.csv
class_id,category_name
10,truck
20,bicycle
30,car
EOF

    cat << 'EOF' > /home/user/data/table_gamma.csv
event_id,class_id,confidence
1,10,0.85
2,10,0.99
3,20,0.92
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
