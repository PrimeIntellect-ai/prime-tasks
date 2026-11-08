#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg golang-go
pip3 install pytest

# Create the video fixture
mkdir -p /app
mkdir -p /tmp/frames

# Use seq instead of brace expansion for sh compatibility
for i in $(seq 1 50); do
    if [ "$i" -eq 2 ] || [ "$i" -eq 7 ] || [ "$i" -eq 11 ] || [ "$i" -eq 15 ] || [ "$i" -eq 19 ] || [ "$i" -eq 22 ] || [ "$i" -eq 27 ] || [ "$i" -eq 31 ] || [ "$i" -eq 36 ] || [ "$i" -eq 40 ] || [ "$i" -eq 43 ] || [ "$i" -eq 47 ] || [ "$i" -eq 49 ]; then
        # Create pure red frame
        ffmpeg -f lavfi -i color=c=red:s=320x240 -frames:v 1 /tmp/frames/frame_$i.png -y >/dev/null 2>&1
    else
        # Create black frame
        ffmpeg -f lavfi -i color=c=black:s=320x240 -frames:v 1 /tmp/frames/frame_$i.png -y >/dev/null 2>&1
    fi
done

# Compile into video
ffmpeg -framerate 10 -i /tmp/frames/frame_%d.png -c:v libx264 -pix_fmt yuv420p /app/evidence.mp4 -y >/dev/null 2>&1
rm -rf /tmp/frames

# Create the user
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
