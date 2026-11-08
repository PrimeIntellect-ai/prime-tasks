#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg binutils gcc
    pip3 install pytest pandas numpy

    mkdir -p /app/system_root/etc
    mkdir -p /app/system_root/home/user/.ssh
    mkdir -p /app/system_root/tmp
    mkdir -p /app/system_root/usr/bin

    # File 1: SUID
    touch /app/system_root/usr/bin/suid_binary
    chmod 4755 /app/system_root/usr/bin/suid_binary

    # File 2: World-Writable
    touch /app/system_root/tmp/world_writable_file
    chmod 777 /app/system_root/tmp/world_writable_file

    # File 3: SSH Key
    echo "BEGIN OPENSSH PRIVATE KEY" > /app/system_root/home/user/.ssh/id_rsa
    chmod 600 /app/system_root/home/user/.ssh/id_rsa

    # File 4: SUID + World-Writable
    touch /app/system_root/tmp/suid_and_ww
    chmod 4777 /app/system_root/tmp/suid_and_ww

    # File 5: Normal file
    touch /app/system_root/etc/passwd
    chmod 644 /app/system_root/etc/passwd

    # File 6: SSH Key + World-Writable
    echo "BEGIN OPENSSH PRIVATE KEY" > /app/system_root/tmp/bad_key
    chmod 777 /app/system_root/tmp/bad_key

    # Generate Truth CSV
    cat << 'EOF' > /app/truth_scores.csv
/app/system_root/usr/bin/suid_binary,25
/app/system_root/tmp/world_writable_file,50
/app/system_root/home/user/.ssh/id_rsa,100
/app/system_root/tmp/suid_and_ww,75
/app/system_root/etc/passwd,0
/app/system_root/tmp/bad_key,150
EOF

    # Generate Malware ELF
    cat << 'EOF' > /tmp/malware.c
#include <stdio.h>
int main() {
    const char* r1 = "[RULE] SUID=+25";
    const char* r2 = "[RULE] WORLD_WRITABLE=+50";
    const char* r3 = "[RULE] SSH_KEY=+100";
    printf("Malware loaded.\n");
    return 0;
}
EOF
    gcc -o /tmp/malware.elf /tmp/malware.c

    # Generate Dummy Video and append ELF
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=20 -c:v libx264 -y /tmp/dummy.mp4
    cat /tmp/dummy.mp4 /tmp/malware.elf > /app/audit_evidence.mp4

    # Cleanup temp files
    rm /tmp/malware.c /tmp/malware.elf /tmp/dummy.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
