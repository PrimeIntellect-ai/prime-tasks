#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/wordlist.txt
admin
password
qwerty
database
changeme
hunter2
secret
admin123
letmein
EOF

    cat << 'EOF' > /home/user/old_config.json
{
  "service": "db",
  "hash_algorithm": "md5",
  "password_hash": "2ab96390c7dbe3439de74d0c9b0b1767"
}
EOF

    chmod -R 777 /home/user
