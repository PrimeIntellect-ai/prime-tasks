#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/incident_data

    # 1. auth_logs.txt
    cat << 'EOF' > /home/user/incident_data/auth_logs.txt
[2023-10-25T14:10:00Z] POST /login username=johndoe status=401
[2023-10-25T14:12:05Z] POST /login username=admin status=401
[2023-10-25T14:15:33Z] POST /login username=admin' OR 1=1-- status=200
[2023-10-25T14:16:01Z] GET /dashboard status=200
EOF

    # 2. backdoor.elf
    cat << 'EOF' > /home/user/backdoor.c
#include <stdio.h>
int main() {
    char c2_server[] = "198.51.100.42";
    printf("Connecting to C2...\n");
    return 0;
}
EOF
    gcc /home/user/backdoor.c -o /home/user/incident_data/backdoor.elf
    rm /home/user/backdoor.c

    # 3. suid_dump.txt
    cat << 'EOF' > /home/user/incident_data/suid_dump.txt
/usr/bin/passwd
/usr/bin/chsh
/usr/bin/gpasswd
/usr/bin/newgrp
/usr/local/bin/backup_script
/usr/bin/sudo
/usr/bin/su
EOF

    # 4. network_traffic.log
    cat << 'EOF' > /home/user/incident_data/network_traffic.log
2023-10-25T14:00:10Z SRC=10.0.0.5 DST=93.184.216.34 PORT=443
2023-10-25T14:15:45Z SRC=10.0.0.5 DST=8.8.8.8 PORT=53
2023-10-25T14:28:00Z SRC=10.0.0.5 DST=198.51.100.42 PORT=4444
2023-10-25T14:32:10Z SRC=10.0.0.5 DST=198.51.100.42 PORT=4444
2023-10-25T14:45:00Z SRC=10.0.0.5 DST=104.21.5.14 PORT=80
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
