#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/build.sh
#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <num_assets>"
    exit 1
fi

echo 0 > /home/user/build_state.db
rm -f /home/user/build.log

process_asset() {
    local item=$1
    # Simulated compilation time
    sleep 0.$RANDOM

    # Read-modify-write race condition
    local count=$(cat /home/user/build_state.db)
    count=$((count + 1))
    echo $count > /home/user/build_state.db
}

for i in $(seq 1 $1); do
    process_asset $i &
done

# Wait for all background jobs to finish
wait

# Verification and recovery loop
retries=0
while [ $retries -lt 5 ]; do
    final_count=$(cat /home/user/build_state.db)
    if [ "$final_count" -eq "$1" ]; then
        echo "Success: $1"
        exit 0
    fi

    echo "Verification failed (expected $1, got $final_count). Retrying..." >> /home/user/build.log
    sleep 0.1
    # BUG: Missing increment for retries, causing infinite loop if final_count is wrong
done

echo "Build failed"
exit 1
EOF

    chmod +x /home/user/build.sh
    chmod -R 777 /home/user
