#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/log_spool/app1/serviceA
    mkdir -p /home/user/log_spool/app2/serviceB

    echo "User test@domain.com logged in." > /home/user/log_spool/app1/serviceA/log1.txt
    printf "id,email,status\n1,admin@secure.com,active\n" > /home/user/log_spool/app1/serviceA/data.csv
    echo '{"event": "signup", "user": "newbie@company.com"}' > /home/user/log_spool/app2/serviceB/event.json
    echo "System booted normally." > /home/user/log_spool/system.txt

    echo "Active log stream..." > /home/user/log_spool/app1/active.txt
    echo "Another active stream..." > /home/user/log_spool/app2/serviceB/active.json

    cat << 'EOF' > /home/user/locker.py
import fcntl
import time
import sys

files = [
    "/home/user/log_spool/app1/active.txt",
    "/home/user/log_spool/app2/serviceB/active.json"
]

fds = []
for f in files:
    fd = open(f, 'a')
    fcntl.flock(fd, fcntl.LOCK_EX) # Exclusive lock
    fds.append(fd)

# Keep holding the locks
while True:
    time.sleep(10)
EOF

    # Ensure the background process starts when the container is executed
    # without hanging the build process
    cat << 'EOF' > /.singularity.d/env/99-locker.sh
#!/bin/sh
if ! pgrep -f "python3 /home/user/locker.py" > /dev/null; then
    nohup python3 /home/user/locker.py >/dev/null 2>&1 &
fi
EOF
    chmod +x /.singularity.d/env/99-locker.sh

    chmod -R 777 /home/user
