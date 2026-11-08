#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg g++ cmake make zlib1g-dev libssl-dev curl
pip3 install pytest

mkdir -p /app/dataset/logs/subdir
ln -s /app/dataset/logs /app/dataset/logs/subdir/loop

# Generate sensor_a.log.gz
for i in $(seq 1 15); do
    echo "[EVENT]" >> /tmp/sensor_a.log
    echo "Data A $i" >> /tmp/sensor_a.log
done
gzip -c /tmp/sensor_a.log > /app/dataset/logs/sensor_a.log.gz

# Generate sensor_b.log.gz (UTF-16LE)
for i in $(seq 1 20); do
    echo "[EVENT]" >> /tmp/sensor_b.log
    echo "Data B $i" >> /tmp/sensor_b.log
done
iconv -f UTF-8 -t UTF-16LE /tmp/sensor_b.log | gzip -c > /app/dataset/logs/sensor_b.log.gz

# Generate 3-second 30fps video
ffmpeg -f lavfi -i testsrc=duration=3:size=640x480:rate=30 -pix_fmt yuv420p /app/experiment.mp4

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
