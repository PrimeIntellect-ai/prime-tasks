#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/process_dump.txt
PID USER COMMAND
101 root /sbin/init
102 root /lib/systemd/systemd-journald
103 admin /usr/bin/python3 /opt/admin/auth.py --user root --hash 5f4dcc3b5aa765d61d8327deb882cf99
104 www-data bash -c "echo 'Y2F0IC9ldGMvc2hhZG93ID4gL3RtcC9vdXQ=' | base64 -d | sh"
105 user top
EOF

    cat << 'EOF' > /home/user/wordlist.txt
admin
admin123
password
qwerty
123456
root
letmein
dragon
EOF

    chmod -R 777 /home/user
