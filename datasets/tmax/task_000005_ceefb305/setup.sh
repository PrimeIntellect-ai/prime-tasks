#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/backup_parts

    cat << 'EOF' > /tmp/dummy1.c
#include <stdio.h>
int main() { printf("Backup target 1\n"); return 0; }
EOF

    cat << 'EOF' > /tmp/dummy2.c
#include <stdio.h>
int main() { printf("Backup target 2\n"); return 1; }
EOF

    gcc /tmp/dummy1.c -o /home/user/incoming/sys_monitor
    gcc /tmp/dummy2.c -o /home/user/incoming/db_sync

    python3 -c 'open("/home/user/incoming/legacy_log.iso88591", "wb").write(b"Syst\xe8me de sauvegarde pr\xeat. R\xe9sum\xe9 des op\xe9rations.\n")'

    chown -R user:user /home/user/incoming
    chown -R user:user /home/user/backup_parts
    chmod -R 777 /home/user
