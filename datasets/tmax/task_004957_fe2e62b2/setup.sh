#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc openssl coreutils
pip3 install pytest

mkdir -p /home/user/conf

# 1. Create the files for integrity checking
echo "server=192.168.1.10" > /home/user/conf/network.ini
echo "port=8080" > /home/user/conf/service.ini
echo "max_connections=100" > /home/user/conf/limits.ini

# Generate manifest (all valid initially)
cd /home/user/conf
sha256sum network.ini service.ini limits.ini > /home/user/manifest.sha256

# Tamper with one file
echo "port=9999" > /home/user/conf/service.ini
cd /home/user

# 2. Create the legacy binary
cat << 'EOF' > /home/user/sec_tool.c
#include <stdio.h>
#include <string.h>

int main() {
    // Hardcoded secret
    const char *secret = "H0undD0g!99_AES_PASS";
    char input[100];
    printf("Enter string to encrypt: ");
    if (fgets(input, 100, stdin) != NULL) {
        printf("Use openssl to encrypt using pass: %s\n", secret);
    }
    return 0;
}
EOF
gcc /home/user/sec_tool.c -o /home/user/sec_tool
rm /home/user/sec_tool.c

# 3. Create the encrypted payloads
PASS="H0undD0g!99_AES_PASS"
PAYLOAD1=$(echo -n "Unauthorized root login detected from 10.0.0.5" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -pass pass:$PASS)
PAYLOAD2=$(echo -n "Data exfiltration blocked on interface eth0" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -pass pass:$PASS)

# Create the log file
cat << EOF > /home/user/syslog.dat
Jan 12 08:00:01 host systemd: Starting up...
Jan 12 08:05:12 host sshd: Accepted publickey for user
Jan 12 09:12:33 host kernel: CRITICAL_ERROR Payload: $PAYLOAD1
Jan 12 10:15:00 host cron: pam_unix(cron:session): session opened
Jan 12 11:22:18 host firewall: CRITICAL_ERROR Payload: $PAYLOAD2
Jan 12 12:00:01 host systemd: Clean up
EOF

# Create user and set permissions
useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
