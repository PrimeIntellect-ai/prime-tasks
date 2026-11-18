#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg zbar-tools cargo qrencode gawk curl
    pip3 install pytest

    mkdir -p /app
    mkdir -p /tmp/qrs

    qrencode -s 10 -o /tmp/qrs/1.png "GRAPH_EDGE;A;B;5"
    qrencode -s 10 -o /tmp/qrs/2.png "GRAPH_EDGE;B;C;10"
    qrencode -s 10 -o /tmp/qrs/3.png "GRAPH_EDGE;A;C;20"
    qrencode -s 10 -o /tmp/qrs/4.png "GRAPH_EDGE;C;D;2"
    qrencode -s 10 -o /tmp/qrs/5.png "GRAPH_EDGE;B;D;15"
    qrencode -s 10 -o /tmp/qrs/6.png "GRAPH_EDGE;D;E;8"

    ffmpeg -framerate 1 -i /tmp/qrs/%d.png -vf "scale=320:320" -c:v libx264 -r 30 -pix_fmt yuv420p /app/dataset_log.mp4

    rm -rf /tmp/qrs

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
