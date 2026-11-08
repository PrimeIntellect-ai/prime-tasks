#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg zbar-tools qrencode g++ imagemagick
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil
    mkdir -p /tmp/frames

    # Generate video frames
    for i in $(seq 1 120); do
        num=$(printf "%03d" $i)
        if [ "$i" -eq 45 ]; then
            qrencode -s 10 -o /tmp/frames/frame_${num}.png "BYPASS_SEED:xyz_hx99_v2"
            convert /tmp/frames/frame_${num}.png -background white -gravity center -extent 320x240 /tmp/frames/frame_${num}.png
        else
            convert -size 320x240 xc:black /tmp/frames/frame_${num}.png
        fi
    done

    ffmpeg -framerate 30 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/incident.mp4
    rm -rf /tmp/frames

    # Create clean corpus
    cat <<EOF > /app/corpus/clean/01.txt
document.pdf
A normal document
EOF

    cat <<EOF > /app/corpus/clean/02.txt
image.png
A nice picture
EOF

    # Create evil corpus
    cat <<EOF > /app/corpus/evil/01.txt
..%2fetc/passwd
clean description
EOF

    cat <<EOF > /app/corpus/evil/02.txt
normal.jpg
<img src=x onerror=alert(1)>
EOF

    cat <<EOF > /app/corpus/evil/03.txt
normal.png
Some text BYPASS_SEED:xyz_hx99_v2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
