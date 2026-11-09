#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg netcat-openbsd socat gawk
    pip3 install pytest

    mkdir -p /app

    # Generate the monitoring video
    cat << 'EOF' > /tmp/gen_video.sh
ffmpeg -y -f lavfi -i "color=c=gray:s=64x64:d=3" \
       -f lavfi -i "color=c=black:s=64x64:d=0.1" \
       -f lavfi -i "color=c=gray:s=64x64:d=2.9" \
       -f lavfi -i "color=c=white:s=64x64:d=1" \
       -f lavfi -i "color=c=gray:s=64x64:d=3" \
       -filter_complex "[0:v][1:v][2:v][3:v][4:v]concat=n=5:v=1:a=0[outv]" \
       -map "[outv]" -pix_fmt yuvj420p -color_range pc /app/monitoring.mp4
EOF
    bash /tmp/gen_video.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
