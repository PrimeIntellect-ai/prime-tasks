#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # 1. Generate Video
    # Create a sequence of 100 black frames
    mkdir -p /tmp/frames
    for i in $(seq 0 99); do
      convert -size 64x64 xc:black /tmp/frames/frame_$(printf "%03d" $i).png
    done
    # Overwrite specific frames with red
    convert -size 64x64 xc:red /tmp/frames/frame_015.png
    convert -size 64x64 xc:red /tmp/frames/frame_042.png
    convert -size 64x64 xc:red /tmp/frames/frame_088.png

    ffmpeg -y -framerate 10 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/dashboard.mp4

    rm -rf /tmp/frames

    # 2. Generate Clean Corpus
    cat << 'EOF' > /app/corpus/clean/clean_1.csv
timestamp,cpu_limit,mem_limit,net_limit
1.0,70,50,50
1.5,80,0,50
2.0,80,50,50
4.2,75,0,100
8.8,50,0,50
EOF

    # 3. Generate Evil Corpus
    cat << 'EOF' > /app/corpus/evil/evil_1.csv
timestamp,cpu_limit,mem_limit,net_limit
1.0,70,50,105
1.5,80,0,50
EOF

    cat << 'EOF' > /app/corpus/evil/evil_2.csv
timestamp,cpu_limit,mem_limit,net_limit
1.0,80,50,50
1.2,85,50,50
1.3,80,50,50
EOF

    cat << 'EOF' > /app/corpus/evil/evil_3.csv
timestamp,cpu_limit,mem_limit,net_limit
1.0,70,50,50
4.2,75,10,100
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
