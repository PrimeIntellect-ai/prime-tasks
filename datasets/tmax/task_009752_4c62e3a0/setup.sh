#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/audit.log
[10:01:22] user: sysadmin - command: ls -la
[10:02:45] user: guest - command: whoami
[10:15:10] user: backup_svc - command: sudo /opt/backup.sh - SUCCESS
[10:16:00] user: web_daemon - command: curl http://localhost
EOF

    cat << 'EOF' > /home/user/shadow.bak
sysadmin:$5$Pepper$7k/3M/r5jG6y5H/Q4mR9uF9bV5yL3yA2uP0lE7yI8I/:18000:0:99999:7:::
backup_svc:$5$NaCl$4/O//jA3uPIt5oB.1G9f2O6mK3E3U/1xT7zP8B3c3y4:18000:0:99999:7:::
web_daemon:$5$Sugar$1lP0vE7yI8I/2mR9uF9bV5yL3yA2uP0lE7yI8I/2mR9:18000:0:99999:7:::
EOF

    cat << 'EOF' > /home/user/wordlist.txt
apple
banana
cherry
admin123
password
qwerty
butterfly
sunflower
dragon
iloveyou
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
