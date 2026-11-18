#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user

    # 1. Create the dummy core dump
    cat << 'EOF' > /home/user/app.core
\x00\x01\x02\x03SOME_BINARY_GARBAGE_HERE\x99\x88\x77
PROCESS_NAME=log_processor
CRITICAL_TZ_OFFSET=-0300
MEMORY_ADDR=0x7fffff
EOF

    # 2. Create the raw logs
    cat << 'EOF' > /home/user/requests.log
2023-10-25T02:30:00Z 100000000.9
2023-10-25T03:30:00Z 100000000.1
2023-10-25T12:00:00Z 100000000.2
2023-10-26T02:30:00Z 100000000.3
2023-10-26T03:30:00Z 100000000.8
EOF

    # 3. Create the unstable calc_variance.sh
    cat << 'EOF' > /home/user/calc_variance.sh
#!/bin/bash
awk '{
    sum += $1
    sumsq += ($1 * $1)
    n++
}
END {
    if (n > 0) {
        mean = sum / n
        variance = (sumsq / n) - (mean * mean)
        printf "%.4f\n", variance
    }
}'
EOF
    chmod +x /home/user/calc_variance.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
