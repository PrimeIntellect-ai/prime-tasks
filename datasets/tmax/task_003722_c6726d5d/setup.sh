#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip procps
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/project/sub

# Create .tmp files
dd if=/dev/urandom of=/home/user/project/small.tmp bs=1K count=5
dd if=/dev/urandom of=/home/user/project/large1.tmp bs=1K count=15
dd if=/dev/urandom of=/home/user/project/sub/large2.tmp bs=1K count=20

# Create config.ini
cat << 'EOF' > /home/user/project/config.ini
[settings]
TIMEOUT=30
LOG_LEVEL=DEBUG
WORKERS=4
EOF

# Create background log writer
cat << 'EOF' > /home/user/project/writer.sh
#!/bin/bash
while true; do
    echo "[INFO] $(date) - Heartbeat ok" >> /home/user/project/live.log
    sleep 1
    echo "[INFO] $(date) - Processing task" >> /home/user/project/live.log
    sleep 1
    echo "[ERROR] $(date) - Task failed
    Traceback (most recent call last):
      File \"app.py\", line 42, in <module>
    ValueError: invalid configuration" >> /home/user/project/live.log
    sleep 2
done
EOF
chmod +x /home/user/project/writer.sh

# Initialize the live log file so it exists for tests
touch /home/user/project/live.log

# Add to bashrc so the background process starts when the agent launches a shell
cat << 'EOF' >> /home/user/.bashrc
if ! pgrep -f writer.sh > /dev/null; then
    nohup /home/user/project/writer.sh > /dev/null 2>&1 &
fi
EOF

chmod -R 777 /home/user
