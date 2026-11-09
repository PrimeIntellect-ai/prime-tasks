#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    mkdir -p /home/user/old_logs
    cd /home/user/old_logs

    cat << 'EOF' > appA.log
INFO: Starting application A
CRITICAL_FAILURE: Disk full on node A1
WARN: High latency
CRITICAL_FAILURE: Database connection lost in app A
INFO: Shutting down application A
EOF

    cat << 'EOF' > appB.log
INFO: Initializing app B
DEBUG: Loading config
CRITICAL_FAILURE: Memory leak detected in B module
CRITICAL_FAILURE: Process crashed in app B unexpectedly
INFO: Restarting app B
EOF

    cat << 'EOF' > appC_ignore.txt
CRITICAL_FAILURE: This should be ignored because it is not a .log file
EOF

    tar -cf appA.tar appA.log
    tar -cf appB.tar appB.log appC_ignore.txt
    rm appA.log appB.log appC_ignore.txt

    tar -cf master_archive.tar appA.tar appB.tar
    rm appA.tar appB.tar

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/old_logs
    chmod -R 777 /home/user
