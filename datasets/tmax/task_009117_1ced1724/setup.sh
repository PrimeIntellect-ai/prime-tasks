#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip bc
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/logs
cat << 'EOF' > /home/user/logs/app1.log
INFO Starting app
INFO Loading config
ERROR Failed to connect to DB
INFO Retrying
ERROR Failed to connect to DB
INFO Giving up
EOF

cat << 'EOF' > /home/user/logs/app2.log
INFO Starting app2
ERROR Null pointer exception
ERROR Timeout
INFO Done
EOF

cat << 'EOF' > /home/user/logs/app3.log
INFO Request received
ERROR Invalid parameters
INFO Processing
ERROR Disk full
ERROR Write failed
INFO Done
EOF

cat << 'EOF' > /home/user/process_logs.sh
#!/bin/bash

LOG_DIR="${LOG_DIR:-/tmp/logs}"
RESULTS_DIR="/home/user/results"
LOCK_DIR="$RESULTS_DIR/lockdir"

process_file() {
    local file=$1
    local err_count=$(grep -c "ERROR" "$file")

    # Acquire lock
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        sleep 0.1
    done

    if [ -f "$RESULTS_DIR/total.txt" ]; then
        current=$(cat "$RESULTS_DIR/total.txt")
    else
        current=0
    fi

    # Update total
    new_total=$((current - err_count))
    echo $new_total > "$RESULTS_DIR/total.txt"

    # Release lock
    rmdir "$LCK_DIR" 2>/dev/null
}

for f in "$LOG_DIR"/*.log; do
    # Skip if no files found
    [ -e "$f" ] || continue
    process_file "$f" &
done

wait

if [ -f "$RESULTS_DIR/total.txt" ]; then
    total_lines=$(cat "$LOG_DIR"/*.log | wc -l)
    total_errors=$(cat "$RESULTS_DIR/total.txt")
    rate=$(echo "$total_errors * 100 / $total_lines" | bc)
    echo "Rate: $rate" > /home/user/final_report.txt
fi
EOF

chmod +x /home/user/process_logs.sh

chmod -R 777 /home/user
