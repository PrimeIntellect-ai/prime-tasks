#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        imagemagick \
        g++ \
        e2fsprogs \
        coreutils

    pip3 install pytest

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Create evil corpus
    echo '{"path": "../../../etc/passwd"}' > /app/corpus/evil/evil1.json
    python3 -c 'print("{\"data\": \"" + "A"*1500 + "\"}")' > /app/corpus/evil/evil2.json
    echo '{"path": "..%2F..%2F"}' > /app/corpus/evil/evil3.json
    echo '{"path": "some\x00path"}' > /app/corpus/evil/evil4.json

    # Create clean corpus
    echo '{"status": "ok"}' > /app/corpus/clean/clean1.json
    echo '{"data": "normal payload"}' > /app/corpus/clean/clean2.json
    echo '{"path": "/var/log/alerts/123.json"}' > /app/corpus/clean/clean3.json

    # Generate video
    mkdir -p /tmp/vid
    cd /tmp/vid
    convert -size 100x100 xc:black black.png
    convert -size 100x100 xc:red red.png

    cat <<EOF > concat.txt
file 'black.png'
duration 13
file 'red.png'
duration 3
file 'black.png'
duration 25
file 'red.png'
duration 2
file 'black.png'
duration 17
file 'black.png'
EOF

    ffmpeg -y -f concat -i concat.txt -vsync vfr -pix_fmt yuv420p -r 1 /app/rack_monitor.mp4
    cd /
    rm -rf /tmp/vid

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
