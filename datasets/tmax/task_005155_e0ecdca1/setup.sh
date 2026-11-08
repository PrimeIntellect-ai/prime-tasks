#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg socat netcat-openbsd
    pip3 install pytest

    mkdir -p /app/bin
    cat << 'EOF' > /app/bin/get_embedding
#!/bin/bash
if [ -z "$1" ] || [ ! -f "$1" ]; then echo "Error: missing file"; exit 1; fi
# Generate a deterministic fake embedding based on file hash
HASH=$(md5sum "$1" | awk '{print $1}')
echo "[0.${HASH:0:4}, 0.${HASH:4:4}, 0.${HASH:8:4}]"
EOF
    chmod +x /app/bin/get_embedding

    mkdir -p /app/data
    # Generate a test video
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 /app/data/source.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
