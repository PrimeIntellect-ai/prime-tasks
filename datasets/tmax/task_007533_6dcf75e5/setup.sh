#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/quarantine
    mkdir -p /home/user/secure_vault
    mkdir -p /home/user/clean_uploads

    cat << 'EOF' > /home/user/upload_log.csv
file1.txt,192.168.1.10,1678881234
file2.txt,10.0.0.5,1678881235
file3.txt,172.16.0.8,1678881236
file4.txt,192.168.1.10,1678881237
file5.txt,203.0.113.42,1678881238
EOF

    cat << 'EOF' > /home/user/quarantine/file1.txt
This is a clean file.
It has no malicious payloads.
EOF

    cat << 'EOF' > /home/user/quarantine/file2.txt
Trying to exploit:
../../../etc/passwd
EOF

    cat << 'EOF' > /home/user/quarantine/file3.txt
Here is my payment info.
My card is 1234567812345678.
Thanks!
EOF

    cat << 'EOF' > /home/user/quarantine/file4.txt
Another clean file from this IP.
EOF

    cat << 'EOF' > /home/user/quarantine/file5.txt
URL encoded traversal: %2e%2e%2fetc%2fshadow
EOF

    chmod -R 777 /home/user
