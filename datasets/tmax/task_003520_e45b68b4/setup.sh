#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git tcpdump tshark coreutils
    pip3 install pytest

    # Create logs directory with space-separated filenames
    mkdir -p /home/user/logs
    echo "Normal log entry" > "/home/user/logs/app_log.txt"
    echo "System initialized" > "/home/user/logs/system log.txt"
    echo "ERROR 55: Critical failure in processing" > "/home/user/logs/error log 1.txt"

    # Set up Git Repo
    mkdir -p /home/user/diag-tool
    cd /home/user/diag-tool
    git init
    git config user.name "Support Admin"
    git config user.email "admin@local"

    # Create script with the bug
    cat << 'EOF' > collect.sh
#!/bin/bash
source /home/user/diag-tool/.env

if [ "$SECRET" == "REPLACEME" ] || [ -z "$SECRET" ]; then 
    echo "Missing secret"
    exit 1
fi
if [ "$PORT" == "0000" ] || [ -z "$PORT" ]; then 
    echo "Missing port"
    exit 1
fi

rm -f /home/user/diag-tool/combined.log

# BUG: ls breaks on spaces
for f in $(ls /home/user/logs/); do
    cat "/home/user/logs/$f" >> /home/user/diag-tool/combined.log 2>/dev/null
done

if grep -q "ERROR 55" /home/user/diag-tool/combined.log 2>/dev/null; then
    echo "{\"status\": \"success\", \"secret\": \"$SECRET\", \"port\": $PORT}" > /home/user/report.json
    echo "Report generated at /home/user/report.json"
else
    echo "Log collection failed. Missing critical errors in combined log."
    exit 1
fi
EOF
    chmod +x collect.sh

    # Commit 1: Initial with secret
    cat << 'EOF' > .env
PORT=0000
SECRET=DIAG-SEC-77bbx9
EOF
    git add collect.sh .env
    git commit -m "Initial commit with diagnostic script"

    # Commit 2: Remove secret
    cat << 'EOF' > .env
PORT=0000
SECRET=REPLACEME
EOF
    git add .env
    git commit -m "Remove hardcoded secret from env file"

    # Generate a small valid pcap file encoded in base64 (contains SYN to port 8088)
    cat << 'EOF' > /tmp/capture.b64
1MOyoQIABAAAAAAAAAAAAAAABAAAAAEAAABf2X1kAAAAABoAAAAYAAAAAgAABgABAAIAAwAEAAAF
CAEQAMB/AAABBID/AAABCLr/AABf2X1kAAAAABoAAAAYAAAAAgAABgABAAIAAwAEAAAFCAEQAMB/
AAABBID/AAABCLo=
EOF
    base64 -d /tmp/capture.b64 > /home/user/capture.pcap
    rm -f /tmp/capture.b64

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/logs /home/user/diag-tool /home/user/capture.pcap
    chmod -R 777 /home/user
