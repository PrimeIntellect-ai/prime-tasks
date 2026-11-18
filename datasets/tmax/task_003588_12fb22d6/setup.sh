#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backup_data/sub_dir
    mkdir -p /home/user/ssh_keys

    touch /home/user/backup_data/file1.tar.gz
    touch /home/user/backup_data/file2.sql
    touch /home/user/backup_data/sub_dir/file3.conf
    touch /home/user/backup_data/sub_dir/file4.log

    touch /home/user/ssh_keys/id_rsa_1
    touch /home/user/ssh_keys/id_rsa_2
    touch /home/user/ssh_keys/id_ecdsa

    cat << 'EOF' > /home/user/system.log
System boot initiated.
User login Password: superSecretPassword!@#
Connecting to remote server...
Error: auth failed.
Generating diagnostic dump.
Included keys:
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACCE0g+5i/j1j0x1X+P0B1L9rYx9gZf1P1W/0w1Y+Qz+8gAAAKB/9/f/f/f/
-----END OPENSSH PRIVATE KEY-----
Diagnostic complete.
Admin authentication Password: admin_pass_xyz
End of log.
EOF

    dd if=/dev/urandom of=/home/user/encryption_key.bin bs=1 count=32 2>/dev/null

    chmod -R 777 /home/user

    # Override specific file permissions required for the task
    chmod 600 /home/user/backup_data/file1.tar.gz
    chmod 644 /home/user/backup_data/file2.sql
    chmod 640 /home/user/backup_data/sub_dir/file3.conf
    chmod 777 /home/user/backup_data/sub_dir/file4.log

    chmod 600 /home/user/ssh_keys/id_rsa_1
    chmod 644 /home/user/ssh_keys/id_rsa_2
    chmod 640 /home/user/ssh_keys/id_ecdsa
