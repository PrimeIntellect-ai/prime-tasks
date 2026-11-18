#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg bc gawk
    pip3 install pytest

    mkdir -p /app/experiment/ground_truth
    mkdir -p /app/tools

    # Generate dummy audio file
    ffmpeg -f lavfi -i "sine=frequency=440:duration=50" -ac 1 -ar 16000 /app/experiment/interview.wav

    # Create mock transcribe tool
    cat << 'EOF' > /app/tools/transcribe
#!/bin/bash
echo "transcription of $1"
EOF
    chmod +x /app/tools/transcribe

    # Create mock text2vec tool
    cat << 'EOF' > /app/tools/text2vec
#!/bin/bash
echo '{"embedding": [0.1, 0.2, 0.3]}'
EOF
    chmod +x /app/tools/text2vec

    # Create user
    useradd -m -s /bin/bash user || true

    # Create flawed pipeline script
    cat << 'EOF' > /home/user/pipeline.sh
#!/bin/bash
# Flawed pipeline with global normalization
MAX_VOL=$(ffmpeg -i /app/experiment/interview.wav -af "volumedetect" -vn -sn -dn -f null /dev/null 2>&1 | grep "max_volume" | awk '{print $5}')
echo "Max volume: $MAX_VOL"
# (rest of the flawed pipeline)
EOF

    chmod -R 777 /home/user
