#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/log_processor.sh
#!/bin/bash
log_file="/home/user/server.log"
output_file="/home/user/clean_logs.txt"

> "$output_file"

process_line() {
    local str="$1"
    # BUG: Infinite recursion on corrupted input
    if [[ "$str" == @@* ]]; then
        process_line "$str" 
    else
        echo "$str" >> "$output_file"
    fi
}

while IFS= read -r line || [[ -n "$line" ]]; do
    process_line "$line"
done < "$log_file"
EOF
    chmod +x /home/user/log_processor.sh

    cat << 'EOF' > /home/user/server.log
INFO: Service started
WARN: High memory usage
@@CRITICAL: Memory corruption detected
INFO: Service stopping
EOF

    dd if=/dev/urandom of=/home/user/core.bin bs=1K count=5 2>/dev/null
    echo -n "SECRET_TOKEN=9942a-f823-xyz-1100" >> /home/user/core.bin
    dd if=/dev/urandom bs=1K count=5 2>/dev/null >> /home/user/core.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
