#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app_logs
    mkdir -p /home/user/archive

    cat << 'EOF' > /home/user/app_logs/app_a.log
[INFO] 2023-10-01 Server started
[ERROR]
Database connection timeout
Retry count: 3
[END ERROR]
[INFO] System stable
EOF

    cat << 'EOF' > /home/user/app_logs/app_b.log
[INFO] Normal operation
[ERROR]
NullPointerException
at com.example.Main.main(Main.java:15)
[END ERROR]
[WARN] High memory usage
[ERROR]
Disk space low
Volume: /dev/sda1
[END ERROR]
EOF

    cat << 'EOF' > /home/user/app_logs/old_app.log
[INFO] Old logs
[ERROR]
This error is old and should be ignored
[END ERROR]
EOF

    # Set timestamps: app_a and app_b are recent, old_app is 5 days old
    touch /home/user/app_logs/app_a.log
    touch /home/user/app_logs/app_b.log
    touch -d "5 days ago" /home/user/app_logs/old_app.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
