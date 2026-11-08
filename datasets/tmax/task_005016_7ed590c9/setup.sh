#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/config

    cat << 'EOF' > /home/user/trace.log
execve("/usr/local/bin/collector", ["collector", "--run"], 0x7ffd1a2b3c40 /* 23 vars */) = 0
brk(NULL)                               = 0x55f9a1b2c000
openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
close(3)                                = 0
openat(AT_FDCWD, "/home/user/config/collector.conf", O_RDONLY) = -1 ENOENT (No such file or directory)
write(2, "Fatal error: missing config\n", 28) = 28
exit_group(1)                           = ?
+++ exited with 1 +++
EOF

    cat << 'EOF' > "/home/user/data/server 1.log"
REQS=150
LATENCY=3
EOF

    cat << 'EOF' > "/home/user/data/server 2.log"
REQS=200
LATENCY=4
EOF

    cat << 'EOF' > /home/user/data/wal.txt
BEGIN TX 1
REQS=50
LATENCY=1
COMMIT TX 1
BEGIN TX 2
REQS=9999
LATENCY=9999
EOF

    cat << 'EOF' > /home/user/aggregate.sh
#!/bin/bash

# Ensure config exists
if [ ! -f "/home/user/config/collector.conf" ]; then
    echo "Error: config missing."
    exit 1
fi

total_reqs=0
total_latency=0

# BUG 1: Breaks on spaces
for f in $(ls /home/user/data/*.log); do
    if [ -f "$f" ]; then
        source "$f"
        total_reqs=$((total_reqs + REQS))
        total_latency=$((total_latency + LATENCY))
    fi
done

# BUG 2: Reads uncommitted WAL entries
while read -r line; do
    if [[ $line == REQS=* ]]; then
        val="${line#*=}"
        total_reqs=$((total_reqs + val))
    elif [[ $line == LATENCY=* ]]; then
        val="${line#*=}"
        total_latency=$((total_latency + val))
    fi
done < /home/user/data/wal.txt

# BUG 3: Broken formula for ms
# total_latency is in seconds.
avg_latency_ms=$(( total_latency / total_reqs * 1000 ))

echo $avg_latency_ms
EOF
    chmod +x /home/user/aggregate.sh

    chmod -R 777 /home/user
