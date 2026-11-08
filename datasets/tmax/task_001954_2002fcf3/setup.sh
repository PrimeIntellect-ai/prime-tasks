#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        openssl \
        cargo \
        rustc \
        fonts-dejavu-core \
        tar \
        gzip

    pip3 install pytest

    # Create directories
    mkdir -p /app/evidence
    mkdir -p /app/verifier/hidden_evil
    mkdir -p /app/verifier/hidden_clean
    mkdir -p /home/user/forensics

    # Generate video with key in frame 1042 (at 30fps, frame 1042 is around 34.7s, duration 50s)
    ffmpeg -f lavfi -i color=c=black:s=320x240:r=30:d=50 \
        -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='KEY-8f4e2b1a9c7d5e6f3b2a1c0d9e8f7a6b':fontcolor=white:fontsize=24:x=10:y=10:enable='eq(n\,1042)'" \
        -c:v libx264 -pix_fmt yuv420p /app/evidence/screen_capture.mp4

    # Create scripts and archive
    mkdir -p /tmp/scripts/evil /tmp/scripts/clean

    cat << 'EOF' > /tmp/scripts/evil/evasion1.sh
#!/bin/bash
if [ -f /.dockerenv ]; then
    exit 0
fi
echo "Payload executing..."
EOF

    cat << 'EOF' > /tmp/scripts/evil/evasion2.sh
#!/bin/bash
grep -q docker /proc/1/cgroup && exit 0
echo "Payload executing..."
EOF

    cat << 'EOF' > /tmp/scripts/clean/backup.sh
#!/bin/bash
tar -czf /backup/logs.tar.gz /var/log
EOF

    cat << 'EOF' > /tmp/scripts/clean/update.sh
#!/bin/bash
apt-get update && apt-get upgrade -y
EOF

    tar -czf /tmp/scripts.tar.gz -C /tmp/scripts evil clean
    openssl enc -aes-256-cbc -pbkdf2 -pass pass:KEY-8f4e2b1a9c7d5e6f3b2a1c0d9e8f7a6b -in /tmp/scripts.tar.gz -out /app/evidence/scripts.tar.gz.enc

    # Create hidden corpora
    cat << 'EOF' > /app/verifier/hidden_evil/hidden_ev1.sh
#!/bin/bash
if [ -f /.dockerenv ]; then exit 1; fi
EOF

    cat << 'EOF' > /app/verifier/hidden_clean/hidden_cl1.sh
#!/bin/bash
echo "Just a normal script"
EOF

    # Cleanup temp
    rm -rf /tmp/scripts /tmp/scripts.tar.gz

    # Setup user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
