#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar gzip
    pip3 install pytest

    mkdir -p /tmp/config_archive
    cat << 'EOF' > /tmp/config_archive/config_changes.log
[2023-10-14T08:35:12Z] [admin] [/etc/nginx/nginx.conf] [MODIFIED] [+45]
[2023-10-14T09:12:00Z] [devop1] [/etc/ssh/sshd_config] [DELETED] [-1200]
[2023-10-14T10:05:00Z] [admin] [/etc/nginx/nginx.conf] [MODIFIED] [+15]
[2023-10-14T11:00:00Z] [system] [/etc/hosts] [MODIFIED] [+20]
This is a malformed line that should be skipped.
[2023-10-15T02:11:12Z] [admin] [/etc/sudoers] [MODIFIED] [+10]
[2023-10-15] admin /etc/hosts MODIFIED +5
[2023-10-15T15:22:11Z] [devop2] [/etc/nginx/nginx.conf] [MODIFIED] [-20]
[2023-10-15T16:00:00Z] [system] [/etc/hosts] [MODIFIED] [-5]
[2023-10-16T08:00:00Z] [admin] [/etc/passwd] [MODIFIED] [+80]
EOF

    cd /tmp/config_archive
    tar -czf audit_logs.tar.gz config_changes.log
    rm config_changes.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
