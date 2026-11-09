#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils tar coreutils
    pip3 install pytest

    mkdir -p /home/user/artifact_store/alpha/beta
    mkdir -p /home/user/artifact_store/gamma
    mkdir -p /tmp/src

    cat << 'EOF' > /tmp/src/app_a.c
#include <stdio.h>
int main() { printf("App A\n"); return 0; }
EOF

    cat << 'EOF' > /tmp/src/app_b.c
#include <stdio.h>
int main() { printf("App B\n"); return 1; }
EOF

    cat << 'EOF' > /tmp/src/app_c.c
#include <stdio.h>
int main() { printf("App C\n"); return 2; }
EOF

    gcc -O0 /tmp/src/app_a.c -o /tmp/src/app_a
    gcc -O2 /tmp/src/app_b.c -o /tmp/src/app_b
    gcc -Os /tmp/src/app_c.c -o /tmp/src/app_c

    cd /tmp/src
    tar -czf /tmp/archive.tar.gz app_a app_b app_c
    cd /tmp
    split -b 2048 archive.tar.gz archive_part_

    bash -c '
    cd /tmp
    parts=(archive_part_*)
    mv "${parts[0]}" /home/user/artifact_store/gamma/
    if [ ${#parts[@]} -ge 2 ]; then
        mv "${parts[1]}" /home/user/artifact_store/alpha/
    fi
    if [ ${#parts[@]} -ge 3 ]; then
        mv "${parts[2]}" /home/user/artifact_store/alpha/beta/
    fi
    if [ ${#parts[@]} -ge 4 ]; then
        mv "${parts[3]}" /home/user/artifact_store/
    fi
    if [ ${#parts[@]} -ge 5 ]; then
        for ((i=4; i<${#parts[@]}; i++)); do
            mv "${parts[$i]}" /home/user/artifact_store/gamma/
        done
    fi
    '

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/artifact_store
    chmod -R 777 /home/user
