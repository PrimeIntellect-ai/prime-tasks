#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace grep coreutils
    pip3 install pytest

    mkdir -p /home/user/data_pipeline

    cat << 'EOF' > /home/user/data_pipeline/events.log
EVENT: 101, REF: 102
EVENT: 102, REF: 103
EVENT: 103, REF: 101
EVENT: 201, REF: 202
EVENT: 202, REF: NONE
EVENT: 301, REF: 301
EVENT: 401, REF: 402
EVENT: 402, REF: 403
EVENT: 403, REF: NONE
EOF

    cat << 'EOF' > /home/user/data_pipeline/process.sh
#!/bin/bash

LOG_FILE="/home/user/data_pipeline/events.log"

trace_chain() {
    local start_id="$1"
    local current_id="$1"

    while true; do
        local next_ref=$(grep "EVENT: $current_id," "$LOG_FILE" | grep -oP 'REF: \K\w+')

        if [ "$next_ref" == "NONE" ] || [ -z "$next_ref" ]; then
            echo "$start_id terminates normally"
            return
        fi

        current_id="$next_ref"
    done
}

while read -r line; do
    id=$(echo "$line" | grep -oP 'EVENT: \K\d+')
    if [ -n "$id" ]; then
        trace_chain "$id"
    fi
done < "$LOG_FILE"
EOF

    chmod +x /home/user/data_pipeline/process.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
