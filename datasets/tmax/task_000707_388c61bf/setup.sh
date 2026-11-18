#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest SpeechRecognition

    mkdir -p /home/user/messy_project
    mkdir -p /app

    cat << 'EOF' > /home/user/project_rules.json
{
  "allowed_extensions": [".log", ".dat", ".bin"],
  "magic_bytes": "4d414749435f484541444552"
}
EOF

    echo "MAGIC_HEADER12345" > /home/user/messy_project/file1.log
    echo "MAGIC_HEADER" > /home/user/messy_project/file2.txt
    echo "1234567890" > /home/user/messy_project/file3.dat
    dd if=/dev/zero of=/home/user/messy_project/large_file.bin bs=1M count=10
    echo -n "MAGIC_HEADER" >> /home/user/messy_project/large_file.bin

    espeak -w /app/voice_memo.wav "Delta protocol override"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
