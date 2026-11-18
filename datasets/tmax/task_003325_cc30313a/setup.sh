#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git ffmpeg bc gawk
    pip3 install pytest

    mkdir -p /app
    # Create a dummy video file
    ffmpeg -f lavfi -i testsrc=duration=1:size=320x240:rate=10 -c:v libx264 -pix_fmt yuv420p /app/incident_capture.mp4

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline
    git init
    git config user.email "eng@example.com"
    git config user.name "Ops Engineer"

    # Commit 1: Good version
    cat << 'EOF' > process_video.sh
#!/bin/bash
video_path=$1
accumulator=9223372036854775800
frame_diff=15
accumulator=$(echo "$accumulator + $frame_diff" | bc)
echo "Frame 144: $accumulator"
EOF
    chmod +x process_video.sh
    git add process_video.sh
    git commit -m "Initial commit"
    git tag v1.0-stable

    for i in {2..5}; do
        echo "# Commit $i" >> process_video.sh
        git commit -am "Commit $i"
    done

    # Commit 6: Buggy version
    cat << 'EOF' > process_video.sh
#!/bin/bash
video_path=$1
accumulator=9223372036854775800
frame_diff=15
accumulator=$(( accumulator + frame_diff ))
echo "Frame 144: $accumulator"
EOF
    git commit -am "Refactor to use native bash arithmetic"

    for i in {7..10}; do
        echo "# Commit $i" >> process_video.sh
        git commit -am "Commit $i"
    done

    mkdir -p /home/user/corpora/evil /home/user/corpora/clean
    cat << 'EOF' > /home/user/corpora/clean/trace1.txt
Frame 1 100
Frame 2 200
Frame 3 300
EOF

    cat << 'EOF' > /home/user/corpora/evil/trace1.txt
Frame 1 9223372036854775800
Frame 2 9223372036854775805
Frame 3 -9223372036854775807
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
