#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create dummy C program and compile it to an ELF binary
    echo "int main() { return 0; }" > dummy.c
    gcc dummy.c -o malware.elf

    # The secret IP is "192.168.137.42"
    # XORing with 0x5A produces "kshtk|rtky}t~h"
    # Base64 encoding "kshtk|rtky}t~h" produces "a3NodGt8cnRreX10fmg="
    echo -n "a3NodGt8cnRreX10fmg=" > payload.bin

    # Inject the payload into the custom section .b64_xor_data
    objcopy --add-section .b64_xor_data=payload.bin malware.elf

    # Create the syslog file with various entries
    cat << 'EOF' > syslog.log
May 14 10:21:05 server sshd[1234]: Accepted password for admin from 10.0.0.5 port 54321 ssh2
May 14 10:25:11 server sshd[1235]: Failed password for root from 192.168.137.42 port 43211 ssh2
May 14 10:30:42 server sshd[1236]: Accepted password for backup_svc from 192.168.137.42 port 54222 ssh2
May 14 10:35:00 server sshd[1237]: Accepted password for webuser from 192.168.1.100 port 33221 ssh2
EOF

    # Cleanup intermediate files
    rm dummy.c payload.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
