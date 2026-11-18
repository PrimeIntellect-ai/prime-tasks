#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/init_data.sh
#!/bin/bash
mkdir -p /home/user/data_source/logs
mkdir -p /home/user/data_source/config

echo "old config data" > /home/user/data_source/config/app.conf
touch -d @1690000000 /home/user/data_source/config/app.conf

echo "recent config data" > /home/user/data_source/config/new_app.conf
touch -d @1700000050 /home/user/data_source/config/new_app.conf

echo "log entry 1" > /home/user/data_source/logs/syslog.1
touch -d @1700000100 /home/user/data_source/logs/syslog.1

echo "active log" > /home/user/data_source/logs/active.log
touch -d @1700000200 /home/user/data_source/logs/active.log

chmod +x /home/user/data_source/logs
chmod +x /home/user/data_source/config
EOF

    cat << 'EOF' > /home/user/hold_locks.sh
#!/bin/bash
# Uses python to hold an exclusive lock on active.log
python3 -c "
import fcntl, time
with open('/home/user/data_source/logs/active.log', 'w') as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    time.sleep(60)
"
EOF

    chmod +x /home/user/init_data.sh
    chmod +x /home/user/hold_locks.sh

    chmod -R 777 /home/user
