#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app
    # Generate a 30-second dummy video
    ffmpeg -f lavfi -i testsrc=duration=30:size=320x240:rate=30 -c:v libx264 /app/fixture.mp4

    mkdir -p /home/user/frames
    mkdir -p /home/user/metadata/clean
    mkdir -p /home/user/metadata/evil

    cat << 'EOF' > /home/user/events.sml
STATE_CHANGE:INIT timestamp=00:00:00.000
STATE_CHANGE:RECORDING timestamp=00:00:05.000
STATE_CHANGE:PAUSED timestamp=00:00:15.000
STATE_CHANGE:STOPPED timestamp=00:00:30.000
EOF

    # Create clean metadata
    cat << 'EOF' > /home/user/metadata/clean/meta1.json
{"title": "My Video", "tags": ["fun", "sun"]}
EOF
    cat << 'EOF' > /home/user/metadata/clean/meta2.json
{"title": "Another Video", "description": "Just a normal video"}
EOF

    # Create evil metadata
    cat << 'EOF' > /home/user/metadata/evil/evil1.json
{"title": "<script>alert(1)</script>", "tags": ["fun"]}
EOF
    cat << 'EOF' > /home/user/metadata/evil/evil2.json
{"title": "Video", "payload": {"a": {"b": {"c": {"d": "too deep"}}}}}
EOF
    cat << 'EOF' > /home/user/metadata/evil/evil3.json
{"query": "SELECT * FROM users;"}
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
