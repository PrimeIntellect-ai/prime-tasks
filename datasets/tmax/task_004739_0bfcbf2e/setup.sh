#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/profiler
    mkdir -p /home/user/mock_proc/100
    mkdir -p /home/user/mock_proc/200
    mkdir -p /home/user/mock_proc/300

    # Create mock stat files. 
    echo "100 (init) S 1 1 1 0 -1 4210944 100 0 10 0 50 20 0 0" > /home/user/mock_proc/100/stat
    echo "100_UPTIME_DIFF=10" > /home/user/mock_proc/100/diff.txt

    echo "200 (worker proc) R 1 1 1 0 -1 4210944 100 0 10 0 120 40 0 0" > /home/user/mock_proc/200/stat
    echo "200_UPTIME_DIFF=10" > /home/user/mock_proc/200/diff.txt

    echo "300 (fast) R 1 1 1 0 -1 4210944 100 0 10 0 5 2 0 0" > /home/user/mock_proc/300/stat
    echo "300_UPTIME_DIFF=0" > /home/user/mock_proc/300/diff.txt

    # Create symlink loop for directory traversal bug
    ln -s /home/user/mock_proc /home/user/mock_proc/sys_links

    # Create environment config with bug (read-only path and missing export)
    cat << 'EOF' > /home/user/profiler/.env
PROFILER_OUTPUT_DIR=/root/output
EOF

    # Create the buggy script
    cat << 'EOF' > /home/user/profiler/sys_profiler.sh
#!/bin/bash
source /home/user/profiler/.env

mkdir -p "$PROFILER_OUTPUT_DIR"

echo "[" > "$PROFILER_OUTPUT_DIR/report.json"
first=true

traverse() {
    local dir="$1"
    for item in "$dir"/*; do
        if [ -d "$item" ]; then
            # Bug: Follows symlinks blindly
            traverse "$item"
        elif [[ "$item" == */stat ]]; then
            pid=$(basename $(dirname "$item"))

            # Bug: Naive awk fails on spaces in process name
            utime=$(awk '{print $14}' "$item")

            diff_file="$(dirname "$item")/diff.txt"
            uptime_diff=$(cut -d'=' -f2 "$diff_file")

            # Bug: Division by zero possible
            metric=$(( utime / uptime_diff ))

            if [ "$first" = true ]; then
                first=false
            else
                echo "," >> "$PROFILER_OUTPUT_DIR/report.json"
            fi
            echo -n "  {\"pid\": \"$pid\", \"metric\": $metric}" >> "$PROFILER_OUTPUT_DIR/report.json"
        fi
    done
}

traverse "/home/user/mock_proc"

echo "" >> "$PROFILER_OUTPUT_DIR/report.json"
echo "]" >> "$PROFILER_OUTPUT_DIR/report.json"
EOF

    chmod +x /home/user/profiler/sys_profiler.sh
    chown -R user:user /home/user/profiler /home/user/mock_proc
    chmod -R 777 /home/user
