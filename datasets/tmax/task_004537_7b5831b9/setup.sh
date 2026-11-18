#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg netcat-openbsd
    pip3 install pytest

    mkdir -p /app
    cd /app

    # Create the video fixture
    ffmpeg -y -f lavfi -i color=c=white:s=320x240:d=1.6333 -pix_fmt yuv420p part1.mp4
    ffmpeg -y -f lavfi -i color=c=black:s=320x240:d=0.0333 -pix_fmt yuv420p part2.mp4
    ffmpeg -y -f lavfi -i color=c=white:s=320x240:d=1.3333 -pix_fmt yuv420p part3.mp4

    cat << 'EOF' > list.txt
file 'part1.mp4'
file 'part2.mp4'
file 'part3.mp4'
EOF
    ffmpeg -y -f concat -i list.txt -c copy incident_capture.mp4
    rm part1.mp4 part2.mp4 part3.mp4 list.txt

    # Create the buggy script
    cat << 'EOF' > /app/bisect_anomaly.sh
#!/bin/bash
# Bisects a video to find a black frame
# Usage: ./bisect_anomaly.sh <video.mp4>

VIDEO=$1
TOTAL_FRAMES=$(ffmpeg -i "$VIDEO" -map 0:v:0 -c copy -f null - 2>&1 | grep -Eo 'frame= *[0-9]+' | grep -Eo '[0-9]+' | tail -n1)

LOW=1
HIGH=$TOTAL_FRAMES

check_frame() {
    local f=$1
    # Extract frame and get mean Y (brightness)
    local mean_y=$(ffmpeg -y -i "$VIDEO" -vf "select='eq(n\,${f})',signalstats" -vframes 1 -f null - 2>&1 | grep -o 'YAVG=[0-9.]*' | cut -d= -f2 | head -n1)
    if [ -z "$mean_y" ]; then echo 255; return; fi
    # Bash doesn't do floats well, cut at decimal
    echo "$mean_y" | cut -d. -f1
}

while [ "$LOW" -le "$HIGH" ]; do
    MID=$(( (LOW + HIGH) / 2 ))
    VAL=$(check_frame $MID)

    # The bug: Wrong binary search logic for a single anomaly.
    # It assumes all frames before anomaly are white, and all after are black.
    # But it's just ONE black frame. Binary search won't work on an unsorted/unstep array!
    # A true delta-debug script for a single anomaly requires a different approach or checking ranges.
    # Wait, the bug is exactly that: it tries to bisect a point anomaly as if it were a step function.
    # Actually, a simpler bug: infinite loop due to off-by-one in binary search

    if [ "$VAL" -lt 50 ]; then
        # found black frame
        echo "Found anomaly at frame: $MID"
        exit 0
    else
        # BUG: Doesn't update LOW or HIGH correctly, causing infinite loop
        # It just randomly goes left or right, or gets stuck.
        LOW=$MID # Missing +1
    fi
done
EOF
    chmod +x /app/bisect_anomaly.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
