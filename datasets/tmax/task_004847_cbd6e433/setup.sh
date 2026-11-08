#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset/logs
    mkdir -p /home/user/dataset/bin

    cat << 'EOF' > /home/user/dataset/config.ini
[EXP-001]
log_file = exp1.log
bin_file = data1.bin

[EXP-002]
log_file = exp2.log
bin_file = data2.bin

[EXP-003]
log_file = exp3.log
bin_file = data3.bin
EOF

    cat << 'EOF' > /home/user/dataset/logs/exp1.log
[2023-10-01 10:00:00] Initialization
System booted normally.
[2023-10-01 10:05:00] Analysis Result
STATUS: SUCCESS
QUALITY: HIGH
Metrics: 0.95
[2023-10-01 10:06:00] Shutdown
EOF

    cat << 'EOF' > /home/user/dataset/logs/exp2.log
[2023-10-02 11:00:00] Initialization
System booted normally.
[2023-10-02 11:05:00] Analysis Result
STATUS: SUCCESS
QUALITY: LOW
Metrics: 0.45
[2023-10-02 11:06:00] Shutdown
EOF

    cat << 'EOF' > /home/user/dataset/logs/exp3.log
[2023-10-03 12:00:00] Initialization
[2023-10-03 12:05:00] Calibration
STATUS: SUCCESS
QUALITY: HIGH
[2023-10-03 12:10:00] Shutdown
EOF

    python3 -c "open('/home/user/dataset/bin/data1.bin', 'wb').write(b'\x00\x01\x02')"
    python3 -c "open('/home/user/dataset/bin/data2.bin', 'wb').write(b'\x03\x04\x05')"
    python3 -c "open('/home/user/dataset/bin/data3.bin', 'wb').write(b'\x06\x07\x08')"

    chown -R user:user /home/user/dataset
    chmod -R 777 /home/user
