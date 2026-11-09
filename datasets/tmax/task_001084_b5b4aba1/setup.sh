#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create subtitles file
    cat << 'EOF' > /tmp/subtitles.srt
1
00:00:01,000 --> 00:00:02,000
1.2.4

2
00:00:02,000 --> 00:00:03,000
2.0.0-rc1

3
00:00:03,000 --> 00:00:04,000
3.1.0
EOF

    # Generate video with embedded subtitles
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=5 -f srt -i /tmp/subtitles.srt -c:v libx264 -c:s mov_text -map 0:v -map 1:s /app/build_metrics.mp4

    # Create oracle script
    cat << 'EOF' > /app/oracle_resolve.sh
#!/bin/bash
# Oracle implementation placeholder
echo "NONE"
EOF
    chmod +x /app/oracle_resolve.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
