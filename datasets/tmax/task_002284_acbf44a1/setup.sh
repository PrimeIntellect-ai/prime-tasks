#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils coreutils file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/evidence

    # Create decoy files
    echo "Nov 12 10:00:00 host kernel: [ 0.000000] Linux version" > /home/user/evidence/system.log
    echo "[Network]" > /home/user/evidence/config.ini
    echo "Timeout=30" >> /home/user/evidence/config.ini
    dd if=/dev/urandom of=/home/user/evidence/user_data.bin bs=1K count=5 2>/dev/null

    # Create the disguised ELF file with the custom section
    cat << 'EOF' > /tmp/malware.c
#include <stdio.h>
__attribute__((section(".key_material"))) const char secret[] = "FLAG{3lf_53ct10n_f0r3n51c5_8821}";
int main() {
    printf("Nothing to see here.\n");
    return 0;
}
EOF

    gcc /tmp/malware.c -o /home/user/evidence/backup.bak
    rm /tmp/malware.c

    chmod -R 777 /home/user
    # Fix permissions for the backup file to match the test requirements
    chmod 0644 /home/user/evidence/backup.bak
