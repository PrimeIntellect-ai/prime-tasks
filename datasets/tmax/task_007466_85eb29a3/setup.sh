#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/ticket_system/data
    mkdir -p /home/user/ticket_system/lib
    mkdir -p /home/user/ticket_system/logs

    # Create data files
    for i in $(seq 1 10); do
        if [ $i -eq 3 ]; then
            printf "5\n5\n4\n" > /home/user/ticket_system/data/batch_$i.txt
        elif [ $i -eq 7 ]; then
            printf "10\n10\n1\n" > /home/user/ticket_system/data/batch_$i.txt
        else
            printf "1\n2\n3\n" > /home/user/ticket_system/data/batch_$i.txt
        fi
    done

    # Create lib/logger_v1.sh
    cat << 'EOF' > /home/user/ticket_system/lib/logger_v1.sh
log_msg() {
    echo "[V1 LOG] $1" >&2
    # BUG: The old logger corrupts the global state used by the math library
    MATH_TMP=""
}
EOF

    # Create lib/logger_v2.sh
    cat << 'EOF' > /home/user/ticket_system/lib/logger_v2.sh
log_msg() {
    echo "[V2 LOG] $1" >&2
}
EOF

    # Create lib/math_lib.sh
    cat << 'EOF' > /home/user/ticket_system/lib/math_lib.sh
calculate_sum() {
    local file=$1
    sum=0
    while read -r num; do
        sum=$((sum + num))
    done < "$file"
    MATH_TMP=$sum
}
EOF

    # Create main script
    cat << 'EOF' > /home/user/ticket_system/calc_checksums.sh
#!/bin/bash
source /home/user/ticket_system/lib/logger_v2.sh
source /home/user/ticket_system/lib/math_lib.sh

for file in "$@"; do
    calculate_sum "$file"
    if [ $((MATH_TMP % 7)) -eq 0 ]; then
        # Intermittent trigger: accidentally sources old conflicting dependency
        source /home/user/ticket_system/lib/logger_v1.sh
        log_msg "Warning: Multiple of 7 detected in $file"
    else
        log_msg "Processed $file"
    fi
    echo "$file: $MATH_TMP"
done
EOF
    chmod +x /home/user/ticket_system/calc_checksums.sh

    # Create mock error log
    cat << 'EOF' > /home/user/ticket_system/logs/error.log
[V2 LOG] Processed data/batch_1.txt
[V2 LOG] Processed data/batch_2.txt
[V1 LOG] Warning: Multiple of 7 detected in data/batch_3.txt
ERROR: Checksum for data/batch_3.txt is empty!
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
