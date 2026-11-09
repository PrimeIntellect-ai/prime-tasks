#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/worker.sh
#!/bin/bash
ID=$1
VERSION=$2
echo "[$(date -Iseconds)] WORKER $ID STARTED VERSION $VERSION" >> /home/user/logs/deploy.log
echo "PADDING LOG ENTRY TO ENSURE IT EXCEEDS ONE HUNDRED BYTES FOR THE INITIAL STARTUP SEQUENCE. THIS IS PADDING." >> /home/user/logs/deploy.log

while true; do
    sleep 60
done
EOF
    chmod +x /home/user/worker.sh

    cat << 'EOF' > /home/user/manifest.json
{
  "target_version": "v2.1.0"
}
EOF

    # Manually create the initial log file so it exists with correct size
    /home/user/worker.sh 1 v1.0.0 &
    PID1=$!
    /home/user/worker.sh 2 v1.0.0 &
    PID2=$!
    /home/user/worker.sh 3 v1.0.0 &
    PID3=$!
    sleep 2
    kill $PID1 $PID2 $PID3 || true

    chmod -R 777 /home/user
