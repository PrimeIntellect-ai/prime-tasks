#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cron curl haproxy nginx
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/corpus/clean /app/corpus/evil /home/user/edge_deploy /home/user/frames

    # Generate a 5-second video
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=1 -c:v libx264 /app/video.mp4

    # Create initial extract.sh
    cat << 'EOF' > /home/user/edge_deploy/extract.sh
#!/bin/bash
mkdir -p frames
ffmpeg -i /app/video.mp4 -r 1 frames/frame_%d.jpg
EOF
    chmod +x /home/user/edge_deploy/extract.sh

    # Setup crontab for root (so test_crontab_exists passes) and user
    echo "* * * * * /home/user/edge_deploy/extract.sh" > /tmp/cronjob
    crontab /tmp/cronjob
    crontab -u user /tmp/cronjob

    # Create corpus files
    cat << 'EOF' > /app/corpus/clean/file1.json
{"sensor_id": "CAM-01", "timestamp": 16777215, "status": "OK"}
EOF
    cat << 'EOF' > /app/corpus/clean/file2.json
{"sensor_id": "CAM-99", "timestamp": 16777220, "status": "OK"}
EOF

    cat << 'EOF' > /app/corpus/evil/file1.json
{"sensor_id": "SYS-01", "timestamp": 16777215, "status": "OK"}
EOF
    cat << 'EOF' > /app/corpus/evil/file2.json
{"sensor_id": "CAM-02", "timestamp": 16777215, "status": "ERROR"}
EOF
    cat << 'EOF' > /app/corpus/evil/file3.json
{"sensor_id": "CAM-03", "timestamp": "invalid", "status": "OK"}
EOF
    cat << 'EOF' > /app/corpus/evil/file4.json
{malformed...
EOF
    cat << 'EOF' > /app/corpus/evil/file5.json
{"sensor_id": "CAM-04", "timestamp": 16777215, "status": "OK", "extra": "data"}
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
