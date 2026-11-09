#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/restore_config.ini
[Settings]
target_dir=/home/user/restored_data
max_retries=4
EOF

    cat << 'EOF' > /home/user/run_restore.sh
#!/bin/bash
STATE_FILE="/home/user/.restore_state"
if [ ! -f "$STATE_FILE" ]; then
    echo 1 > "$STATE_FILE"
fi

ATTEMPT=$(cat "$STATE_FILE")

if [ "$ATTEMPT" -lt 3 ]; then
    echo $((ATTEMPT + 1)) > "$STATE_FILE"
    echo "Network misconfiguration detected. Failing..." >&2
    exit 1
else
    # Succeeds on the 3rd attempt, resets state for future testing
    rm -f "$STATE_FILE"
    echo "Restore successful."
    exit 0
fi
EOF

    chmod +x /home/user/run_restore.sh
    chown -R user:user /home/user
    chmod -R 777 /home/user
