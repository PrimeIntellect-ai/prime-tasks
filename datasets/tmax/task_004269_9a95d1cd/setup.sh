#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y ffmpeg tesseract-ocr imagemagick

    # Fix ImageMagick policy to allow text to image
    sed -i 's/none/read,write/g' /etc/ImageMagick-6/policy.xml || true

    mkdir -p /app/frames
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Generate video frames
    convert -size 800x600 xc:white -fill black -pointsize 48 -gravity center -annotate +0+0 "T100 HOLDS R50" /app/frames/frame001.png
    convert -size 800x600 xc:white -fill black -pointsize 48 -gravity center -annotate +0+0 "T101 HOLDS R51" /app/frames/frame002.png
    convert -size 800x600 xc:white -fill black -pointsize 48 -gravity center -annotate +0+0 "T100 WAITS_FOR R51" /app/frames/frame003.png
    convert -size 800x600 xc:white -fill black -pointsize 48 -gravity center -annotate +0+0 "T102 HOLDS R52" /app/frames/frame004.png
    convert -size 800x600 xc:white -fill black -pointsize 48 -gravity center -annotate +0+0 "T101 WAITS_FOR R50" /app/frames/frame005.png

    # Create video
    ffmpeg -framerate 1 -i /app/frames/frame%03d.png -c:v libx264 -r 1 -pix_fmt yuv420p /app/pipeline_monitor.mp4
    rm -rf /app/frames

    # Populate evil corpus
    cat << 'EOF' > /app/corpora/evil/evil1.json
{
  "edges": [
    {"from": "A", "to": "R1", "type": "WAITS_FOR"},
    {"from": "B", "to": "R1", "type": "HOLDS"},
    {"from": "B", "to": "R2", "type": "WAITS_FOR"},
    {"from": "A", "to": "R2", "type": "HOLDS"}
  ]
}
EOF

    cat << 'EOF' > /app/corpora/evil/evil2.json
{
  "edges": [
    {"from": "T1", "to": "R1", "type": "HOLDS"},
    {"from": "T2", "to": "R2", "type": "HOLDS"},
    {"from": "T3", "to": "R3", "type": "HOLDS"},
    {"from": "T1", "to": "R2", "type": "WAITS_FOR"},
    {"from": "T2", "to": "R3", "type": "WAITS_FOR"},
    {"from": "T3", "to": "R1", "type": "WAITS_FOR"}
  ]
}
EOF

    # Populate clean corpus
    cat << 'EOF' > /app/corpora/clean/clean1.json
{
  "edges": [
    {"from": "A", "to": "R1", "type": "WAITS_FOR"},
    {"from": "B", "to": "R1", "type": "HOLDS"},
    {"from": "B", "to": "R2", "type": "WAITS_FOR"},
    {"from": "C", "to": "R2", "type": "HOLDS"}
  ]
}
EOF

    cat << 'EOF' > /app/corpora/clean/clean2.json
{
  "edges": [
    {"from": "T1", "to": "R1", "type": "HOLDS"},
    {"from": "T2", "to": "R1", "type": "WAITS_FOR"},
    {"from": "T3", "to": "R1", "type": "WAITS_FOR"}
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
