#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk coreutils
    pip3 install pytest

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=15:size=320x240:rate=30 -c:v libx264 -pix_fmt yuv420p /app/surveillance.mp4

    cat << 'EOF' > /app/oracle.sh
#!/bin/bash
declare -A seen
while read -r event_id timestamp; do
    if [[ -z "$timestamp" ]]; then continue; fi
    if [[ ${seen[$timestamp]} == 1 ]]; then
        echo "DUPLICATE $timestamp"
    else
        seen[$timestamp]=1
        hash=$(ffmpeg -ss "$timestamp" -i /app/surveillance.mp4 -vframes 1 -f image2 -c:v mjpeg -s 160x120 - 2>/dev/null | sha256sum | awk '{print $1}')
        echo "NEW $timestamp $hash"
    fi
done
EOF
    chmod +x /app/oracle.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
