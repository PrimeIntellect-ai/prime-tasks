#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_logs

    cat << 'EOF' > /home/user/raw_logs/node1.log
=== START TRANSACTION 101 ===
Timestamp: 2023-10-25 10:00:00
Status: SUCCESS
Details:
  Copied 500 blocks
  Latency 12ms
=== END TRANSACTION 101 ===
=== START TRANSACTION 102 ===
Timestamp: 2023-10-25 10:05:00
Status: FAILED
Details:
  Disk quota exceeded
  Retried 3 times
  Stack trace:
    File "a.py", line 1
=== END TRANSACTION 102 ===
=== START TRANSACTION 103 ===
Timestamp: 2023-10-25 10:10:00
Status: SUCCESS
Details:
  Ok
=== END TRANSACTION 103 ===
EOF

    cat << 'EOF' > /home/user/raw_logs/node2.log
=== START TRANSACTION 201 ===
Timestamp: 2023-10-25 11:00:00
Status: FAILED
Details:
  Network timeout
=== END TRANSACTION 201 ===
=== START TRANSACTION 202 ===
Timestamp: 2023-10-25 11:05:00
Status: FAILED
Details:
  I/O Error on device
=== END TRANSACTION 202 ===
EOF

    chmod -R 777 /home/user
