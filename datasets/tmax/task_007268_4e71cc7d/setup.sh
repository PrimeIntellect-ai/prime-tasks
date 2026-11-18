#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_metrics.log
2023-10-12T10:00:00Z,OK,METRIC_NODE_A_001
2023-10-12T10:00:05Z,OK,METRIC_NODE_B_002
2023-10-12T10:00:10Z,WARN,METRIC_NODE_C_003
2023-10-12T10:00:15Z,ERR,SRE_CORRUPT_0x8F9A
2023-10-12T10:00:20Z,OK,METRIC_NODE_A_004
EOF

    cat << 'EOF' > /home/user/uptime_monitor.log
[INFO] Starting uptime monitor service v1.2.4
[INFO] Loading raw metrics from raw_metrics.log...
[INFO] Processed 3 metrics successfully.
[ERROR] Memory dump generated at memory.dmp
thread 'main' panicked at 'Invalid metric format detected! Metric structure corrupted.', src/main.rs:42:17
stack backtrace:
   0: rust_begin_unwind
             at /rustc/...,
   1: core::panicking::panic_fmt
             at /rustc/...
   2: uptime_monitor::process_metrics::validate_metric
             at src/main.rs:42:17
   3: uptime_monitor::main
             at src/main.rs:18:13
EOF

    python3 -c '
import struct
with open("/home/user/memory.dmp", "wb") as f:
    f.write(b"\x00\x01\x02\x03\x04\x05")
    f.write(b"SRE_CORRUPT_0x8F9A")
    f.write(b"\xFE\xFF\x00\x00")
'

    chmod -R 777 /home/user
