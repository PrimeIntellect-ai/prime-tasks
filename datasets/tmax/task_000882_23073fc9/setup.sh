#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming_logs
    cd /home/user/incoming_logs

    # Archive 1 (Safe)
    mkdir -p safe1/logs
    cat << 'EOF' > safe1/logs/app1.log
[2023-10-01 10:00:00] ERROR_START
Connection timeout
Retrying...
Disk-Impact: 1500
[2023-10-01 10:00:05] ERROR_END
Some regular log line here
[2023-10-01 10:05:00] ERROR_START
Crash dump generated
Disk-Impact: 500
[2023-10-01 10:05:01] ERROR_END
EOF
    tar -czf archive1.tar.gz -C safe1 logs/app1.log

    # Archive 2 (Malicious - ../)
    mkdir -p mal2
    touch mal2/shadow
    tar -czf archive2.tar.gz -C mal2 --transform='s|^shadow|../etc/shadow|' shadow

    # Archive 3 (Safe)
    mkdir -p safe3/logs
    cat << 'EOF' > safe3/logs/app2.log
Normal operational log
[2023-10-02 11:00:00] ERROR_START
Core dumped
Disk-Impact: 3500
[2023-10-02 11:00:05] ERROR_END
EOF
    tar -czf archive3.tar.gz -C safe3 logs/app2.log

    # Archive 4 (Malicious - absolute path)
    mkdir -p mal4
    touch mal4/secret.txt
    tar -czf archive4.tar.gz -C mal4 --transform='s|^secret.txt|/root/secret.txt|' secret.txt

    rm -rf safe1 mal2 safe3 mal4

    chmod -R 777 /home/user
