#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups/node_alpha
    mkdir -p /home/user/backups/node_beta
    mkdir -p /home/user/backups/node_gamma

    cat << 'EOF' > /home/user/backups/storage_policy.ini
[Policy]
target_dirs=node_alpha,node_gamma
retention_days=90
EOF

    # node_alpha data
    cat << 'EOF' > /home/user/backups/node_alpha/usage.csv
file1.tmp,tmp,1048576,100
file2.log,log,5000,120
file3.cache,cache,2048,50
file4.cache,cache,5000000,95
EOF
    cat << 'EOF' > /home/user/backups/node_alpha/dummy.txt
dummy data
EOF
    tar -czf /home/user/backups/node_alpha/data.tar.gz -C /home/user/backups/node_alpha usage.csv dummy.txt
    rm /home/user/backups/node_alpha/usage.csv /home/user/backups/node_alpha/dummy.txt

    # node_beta data (should be ignored)
    cat << 'EOF' > /home/user/backups/node_beta/usage.csv
file_ignore.tmp,tmp,99999999,200
EOF
    tar -czf /home/user/backups/node_beta/data.tar.gz -C /home/user/backups/node_beta usage.csv
    rm /home/user/backups/node_beta/usage.csv

    # node_gamma data
    cat << 'EOF' > /home/user/backups/node_gamma/usage.csv
a.tmp,tmp,2000000,200
b.cache,cache,150000,80
EOF
    cat << 'EOF' > /home/user/backups/node_gamma/notes.md
ignore me
EOF
    tar -czf /home/user/backups/node_gamma/data.tar.gz -C /home/user/backups/node_gamma usage.csv notes.md
    rm /home/user/backups/node_gamma/usage.csv /home/user/backups/node_gamma/notes.md

    chown -R user:user /home/user/backups
    chmod -R 777 /home/user
