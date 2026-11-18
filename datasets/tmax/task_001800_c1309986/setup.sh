#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        nginx \
        git \
        gcc \
        imagemagick \
        fcgiwrap \
        spawn-fcgi

    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Create ACL file
    cat << 'EOF' > /app/acl.txt
alice
bob
charlie
EOF

    # Create Clean Corpora
    cat << 'EOF' > /app/corpora/clean/1.alloc
USER: alice
MOUNT: /mnt/storage/data1
SIZE: 50
EOF

    cat << 'EOF' > /app/corpora/clean/2.alloc
USER: bob
MOUNT: /mnt/storage/data2
SIZE: 63
EOF

    # Create Evil Corpora
    cat << 'EOF' > /app/corpora/evil/1.alloc
USER: eve
MOUNT: /mnt/storage/data
SIZE: 50
EOF

    cat << 'EOF' > /app/corpora/evil/2.alloc
USER: alice
MOUNT: /mnt/storage/../etc
SIZE: 50
EOF

    cat << 'EOF' > /app/corpora/evil/3.alloc
USER: bob
MOUNT: /mnt/storage/data
SIZE: 64
EOF

    cat << 'EOF' > /app/corpora/evil/4.alloc
USER: charlie
MOUNT: /tmp/data
SIZE: 10
EOF

    # Generate video with red flash on frame 37
    mkdir -p /tmp/frames
    for i in $(seq 1 50); do
        if [ $i -eq 37 ]; then
            convert -size 100x100 xc:red /tmp/frames/frame_$(printf "%03d" $i).png
        else
            convert -size 100x100 xc:black /tmp/frames/frame_$(printf "%03d" $i).png
        fi
    done
    ffmpeg -framerate 10 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/san_monitoring.mp4
    rm -rf /tmp/frames

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
