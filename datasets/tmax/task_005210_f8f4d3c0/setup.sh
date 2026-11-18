#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc espeak gawk coreutils
pip3 install pytest

mkdir -p /app/cgi-bin
mkdir -p /app/audit_logs
chmod 755 /app/cgi-bin

# Generate audio file
echo "reddragon" | espeak -w /app/admin_note.wav

# Generate legacy auditor
cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
int main() {
    printf("Expected header: X-Audit-Auth\n");
    printf("Salt: _salty_\n");
    return 0;
}
EOF
gcc /tmp/legacy.c -o /app/legacy_auditor
rm /tmp/legacy.c
chmod +x /app/legacy_auditor

# Generate token hash
echo -n "reddragon_salty_42" | sha256sum | awk '{print $1}' > /app/token_hash.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
