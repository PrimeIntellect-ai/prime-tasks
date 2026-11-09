#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/services/pids
    chmod 755 /home/user/services/pids

    cat << 'EOF' > /home/user/services/dummy_service.py
import sys
import time

if len(sys.argv) != 2:
    sys.exit(1)
port = sys.argv[1]
# Just sleep forever to simulate a running service
while True:
    time.sleep(10)
EOF

    cat << 'EOF' > /home/user/services/start_single.sh
#!/bin/bash
PORT=$1
nohup python3 /home/user/services/dummy_service.py $PORT > /dev/null 2>&1 &
echo $! > /home/user/services/pids/$PORT.pid
EOF
    chmod +x /home/user/services/start_single.sh

    cat << 'EOF' > /home/user/net_diag.log
INFO: 2023-10-01 10:00:00 - Ping 127.0.0.1:8001 OK
ERROR: 2023-10-01 10:01:23 - Ping 127.0.0.1:8002 FAILED (Timeout)
INFO: 2023-10-01 10:02:00 - Ping 127.0.0.1:8001 OK
CRITICAL: 2023-10-01 10:05:11 - Connection refused 127.0.0.1:8003
INFO: 2023-10-01 10:06:00 - Ping 127.0.0.1:8001 OK
DEBUG: 2023-10-01 10:07:00 - Retry 127.0.0.1:8002 FAILED (Host unreachable)
EOF

    chown -R user:user /home/user

    # Start services
    su - user -c "/home/user/services/start_single.sh 8001"
    su - user -c "/home/user/services/start_single.sh 8002"
    su - user -c "/home/user/services/start_single.sh 8003"

    chmod -R 777 /home/user
