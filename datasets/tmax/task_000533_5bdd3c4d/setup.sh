#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo espeak ffmpeg
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "Administrator log day forty two. The incremental backup stream has been corrupted by a path traversal payload. Manual extraction is required."

    cat << 'EOF' > /tmp/make_tar.py
import tarfile
import io

with tarfile.open("/app/backup.tar.gz", "w:gz") as tar:
    tar.add("/app/voicemail.wav", arcname="voicemail.wav")

    meta_info = tarfile.TarInfo("backup_meta.json")
    meta_data = b'{"version": 1}'
    meta_info.size = len(meta_data)
    tar.addfile(meta_info, io.BytesIO(meta_data))

    malicious_info = tarfile.TarInfo("../malicious_overwrite.sh")
    malicious_data = b'echo "hacked"'
    malicious_info.size = len(malicious_data)
    tar.addfile(malicious_info, io.BytesIO(malicious_data))
EOF
    python3 /tmp/make_tar.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
