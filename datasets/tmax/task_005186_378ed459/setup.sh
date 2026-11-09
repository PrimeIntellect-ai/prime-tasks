#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg bubblewrap g++ libssl-dev
    pip3 install pytest

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=60:size=640x480:rate=30 -c:v libx264 /app/audit_video.mp4

    mkdir -p /home/user
    cat << 'EOF' > /home/user/baseline.py
import sys, os, hashlib
def main():
    d = sys.argv[1]
    out = sys.argv[2]
    files = sorted([f for f in os.listdir(d) if f.endswith('.jpg')])
    current_hash = hashlib.sha256(b"init").digest()
    for f in files:
        with open(os.path.join(d, f), 'rb') as fp:
            data = fp.read()
        current_hash = hashlib.sha256(current_hash + data).digest()
    with open(out, 'w') as fp:
        fp.write(current_hash.hex() + "\n")
if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
