#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendored/bash-log-utils-1.4.0 \
             /app/corpora/evil \
             /app/corpora/clean \
             /tmp/fs_recovery_img/blocks \
             /home/user

    # Create vendored env_setup.sh
    cat << 'EOF' > /app/vendored/bash-log-utils-1.4.0/env_setup.sh
#!/bin/bash
alias awk='/usr/bin/false'
EOF
    chmod +x /app/vendored/bash-log-utils-1.4.0/env_setup.sh

    # Create vendored process_entry.sh with infinite recursion bug
    cat << 'EOF' > /app/vendored/bash-log-utils-1.4.0/process_entry.sh
#!/bin/bash
source "$(dirname "$0")/env_setup.sh"
shopt -s expand_aliases

parse_line() {
    local line="$1"
    if [ ${#line} -gt 20 ]; then
        # Infinite recursion bug without base case reduction
        parse_line "$line"
    else
        echo "Parsed: $line" | awk '{print $0}'
    fi
}

if [ $# -gt 0 ]; then
    parse_line "$1"
else
    while IFS= read -r line; do
        parse_line "$line"
    done
fi
EOF
    chmod +x /app/vendored/bash-log-utils-1.4.0/process_entry.sh

    # Populate fs recovery image
    cat << 'EOF' > /tmp/fs_recovery_img/inode_table.txt
crash_evidence.log: block_001 block_002 block_003
EOF
    echo "CRASH LOG START" > /tmp/fs_recovery_img/blocks/block_001
    echo "ERROR: Buffer overflow detected in module log_parser" > /tmp/fs_recovery_img/blocks/block_002
    echo "CRASH LOG END" > /tmp/fs_recovery_img/blocks/block_003

    # Populate corpora
    for i in $(seq 1 50); do
        # Clean corpus
        echo "2023-10-01 12:00:00 INFO [main] Normal log entry $i" > /app/corpora/clean/log_$i.txt

        # Evil corpus
        if [ $((i % 3)) -eq 0 ]; then
            echo "2023-10-01 12:00:00 ERROR [main] Payload contains 0xNaN in entry $i" > /app/corpora/evil/log_$i.txt
        elif [ $((i % 3)) -eq 1 ]; then
            echo "2023-10-01 12:00:00 ERROR [main] Triggered infinity_loop_ptr $i" > /app/corpora/evil/log_$i.txt
        else
            echo "2023-10-01 12:00:00 ERROR [main] deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef $i" > /app/corpora/evil/log_$i.txt
        fi
    done

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /app/vendored
    chmod -R 777 /app/vendored
    chmod -R 777 /home/user
