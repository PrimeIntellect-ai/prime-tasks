#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr fonts-dejavu wget
    pip3 install pytest

    # Install websocat
    wget -qO /usr/local/bin/websocat https://github.com/vi/websocat/releases/download/v1.11.0/websocat.x86_64-unknown-linux-musl
    chmod +x /usr/local/bin/websocat

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/project

    # Generate video fixture
    ffmpeg -y -f lavfi -i color=c=black:s=640x480:d=2 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='BUILD LOG':fontcolor=white:fontsize=24:x=10:y=10, drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='CORRUPTION_DETECTED\: lib_renderer':fontcolor=red:fontsize=24:x=10:y=50:enable='eq(n\,41)'" -c:v libx264 /app/build_capture.mp4

    # Generate dependency graph
    cat << 'EOF' > /home/user/project/deps.txt
main: lib_renderer lib_audio
lib_renderer: lib_gl lib_math
lib_audio: core_utils
lib_gl: core_utils
lib_math: core_utils
core_utils: 
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
