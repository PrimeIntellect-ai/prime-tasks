#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc jq coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/perf_logs.txt
[2023-10-01 10:00:01] INFO system started
[2023-10-01 10:00:02] DEBUG metrics - load:10 req/s, memory:512MB, latency:25 ms
[2023-10-01 10:00:03] WARN GC pause
[2023-10-01 10:00:04] DEBUG metrics - load:20 req/s, memory:515MB, latency:45 ms
[2023-10-01 10:00:05] DEBUG metrics - load:30 req/s, memory:520MB, latency:65 ms
[2023-10-01 10:00:06] INFO user login
[2023-10-01 10:00:07] DEBUG metrics - load:40 req/s, memory:530MB, latency:85 ms
[2023-10-01 10:00:08] DEBUG metrics - load:50 req/s, memory:540MB, latency:105 ms
EOF

    chmod -R 777 /home/user
