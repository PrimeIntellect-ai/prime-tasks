#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/webroot/cgi-bin

# Create the malicious SUID binary
cat << 'EOF' > /home/user/system_health.c
#include <stdio.h>
int main() {
    const char *key = "AUTH_BYPASS_KEY=XyZ89Qlp";
    printf("System Health OK\n");
    return 0;
}
EOF
gcc /home/user/system_health.c -o /home/user/webroot/cgi-bin/system_health
rm /home/user/system_health.c

# Create benign files
cp /bin/echo /home/user/webroot/cgi-bin/ping_test
cp /bin/ls /home/user/webroot/cgi-bin/list_dir

chmod -R 777 /home/user

# Restore exact permissions required for the task
chmod 4755 /home/user/webroot/cgi-bin/system_health
chmod 755 /home/user/webroot/cgi-bin/ping_test
chmod 755 /home/user/webroot/cgi-bin/list_dir
