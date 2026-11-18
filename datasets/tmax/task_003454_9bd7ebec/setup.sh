#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace lsof procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/setup.sh
#!/bin/bash

LOG_DIR="/home/user/app/logs"
LOCK_DIR="/home/user/app/locks"

# Bug: misspelled variable LOK_DIR instead of LOCK_DIR
mkdir -p "$LOG_DIR"
mkdir -p "$LOK_DIR"

touch "$LOCK_DIR/a.lock"
touch "$LOCK_DIR/b.lock"
EOF

    cat << 'EOF' > /home/user/app/log_aggregator.sh
#!/bin/bash

LOCK_A="/home/user/app/locks/a.lock"
LOCK_B="/home/user/app/locks/b.lock"

worker_one() {
    exec 200>"$LOCK_A"
    flock 200
    sleep 1
    exec 201>"$LOCK_B"
    flock 201

    echo "Worker 1 done" >> /home/user/app/logs/result.log

    flock -u 201
    flock -u 200
}

worker_two() {
    exec 201>"$LOCK_B"
    flock 201
    sleep 1
    exec 200>"$LOCK_A"
    flock 200

    echo "Worker 2 done" >> /home/user/app/logs/result.log

    flock -u 200
    flock -u 201
}

worker_one &
worker_two &

wait
echo "All done" >> /home/user/app/logs/result.log
EOF

    chmod +x /home/user/app/setup.sh /home/user/app/log_aggregator.sh
    chmod -R 777 /home/user
