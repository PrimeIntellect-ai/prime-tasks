#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs
    mkdir -p /home/user/processed
    mkdir -p /home/user/archive
    mkdir -p /home/user/staging

    cat << 'EOF' > /home/user/archiver.sh
#!/bin/bash
# archiver.sh - Moves files listed in queue.txt to the archive directory
# and cleans them up from the processed directory.

QUEUE="/home/user/staging/queue.txt"
ARCHIVE_DIR="/home/user/archive"
PROCESSED_DIR="/home/user/processed"

if [ ! -f "$QUEUE" ]; then
    echo "No queue file found."
    exit 0
fi

# Bug: iterating over cat output causes word splitting and glob expansion
for file in $(cat "$QUEUE"); do
    if [ -n "$file" ]; then
        cp "$PROCESSED_DIR/$file" "$ARCHIVE_DIR/" 2>/dev/null
        rm $PROCESSED_DIR/$file 2>/dev/null
        echo "Archived $file"
    fi
done

rm "$QUEUE"
EOF
    chmod +x /home/user/archiver.sh

    cat << 'EOF' > /home/user/logs/app.log
[2023-10-25 13:55:01] INFO - Report generation started.
[2023-10-25 13:56:12] INFO - Generated: daily_summary.csv
[2023-10-25 13:58:45] INFO - Generated: user_metrics.json
[2023-10-25 13:59:30] WARN - Title extraction failed, using default generic wildcard title.
[2023-10-25 13:59:31] INFO - Generated: *
[2023-10-25 14:00:05] INFO - Report generation complete.
EOF

    cat << 'EOF' > /home/user/logs/syslog
Oct 25 13:50:00 server cron[1204]: (user) CMD (/home/user/archiver.sh >> /home/user/logs/archiver.log 2>&1)
Oct 25 14:00:00 server cron[1345]: (user) CMD (/home/user/archiver.sh >> /home/user/logs/archiver.log 2>&1)
Oct 25 14:10:00 server cron[1489]: (user) CMD (/home/user/archiver.sh >> /home/user/logs/archiver.log 2>&1)
EOF

    cat << 'EOF' > /home/user/logs/archiver.log
Archived daily_summary.csv
Archived user_metrics.json
Archived *
EOF

    chmod -R 777 /home/user
