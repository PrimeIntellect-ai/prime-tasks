#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick fonts-dejavu-core tesseract-ocr
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/edges.txt
REPLICATE: db-primary -> db-replica-1
REPLICATE: db-primary -> db-replica-2
REPLICATE: db-replica-1 -> db-analytics-1
REPLICATE: db-replica-2 -> db-reporting
REPLICATE: db-analytics-1 -> db-archive
EOF

    mkdir -p /tmp/frames
    split -l 1 /tmp/edges.txt /tmp/frames/edge_
    c=1
    for f in /tmp/frames/edge_*; do
      convert -size 640x480 xc:black -font DejaVu-Sans -pointsize 36 -fill white -gravity center -draw "text 0,0 '$(cat $f)'" /tmp/frames/frame_$(printf "%03d" $c).png
      c=$((c+1))
    done

    ffmpeg -framerate 1 -i /tmp/frames/frame_%03d.png -c:v libx264 -r 30 -pix_fmt yuv420p /app/backup_topology.mp4

    rm -rf /tmp/frames /tmp/edges.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
