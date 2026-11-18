#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk sed
    pip3 install pytest flask fastapi uvicorn requests pandas

    mkdir -p /app
    cat << 'EOF' > /app/detections.csv
frame_id,object_id,x,y,w,h
1.0,101.0,10,10,50,50
2.0,NaN,20,20,40,40
NaN,101.0,30,30,50,50
3.0,102.0,5,5,10,10
12.0,101.0,15,15,50,60
EOF

    # Generate a 10-second mp4 video at 30fps
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x360:rate=30 -c:v libx264 -pix_fmt yuv420p /app/traffic.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
