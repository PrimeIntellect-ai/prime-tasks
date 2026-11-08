#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Clean corpus
    cat << 'EOF' > /app/corpora/clean/clean1.json
{"version": "1.0.0", "build_steps": [{"lang": "python", "cmd": "pip install"}]}
EOF
    cat << 'EOF' > /app/corpora/clean/clean2.json
{"version": "2.1.0", "orchestration": {"cpp": {"commands": ["make"]}}}
EOF

    # Evil corpus
    cat << 'EOF' > /app/corpora/evil/evil1.json
{"version": "1.0", "build_steps": [{"lang": "python", "cmd": "pip install"}]}
EOF
    cat << 'EOF' > /app/corpora/evil/evil2.json
{"version": "1.0.0", "build_steps": [{"lang": "java", "cmd": "mvn"}]}
EOF

    # Generate SRT
    cat << 'EOF' > /tmp/input.srt
1
00:00:01,000 --> 00:00:02,000
{"version": "1.0.0", "build_steps": [{"lang": "python", "cmd": "pip install"}]}

2
00:00:03,000 --> 00:00:04,000
{"version": "1.0", "build_steps": [{"lang": "python", "cmd": "pip install"}]}
EOF

    # Generate video with embedded subtitles
    ffmpeg -f lavfi -i color=c=black:s=128x128:r=1:d=5 -c:v libx264 /tmp/video.mp4
    ffmpeg -i /tmp/video.mp4 -i /tmp/input.srt -c copy -c:s mov_text /app/build_dashboard_capture.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
