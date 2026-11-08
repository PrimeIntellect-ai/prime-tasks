#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git bc gawk
    pip3 install pytest

    mkdir -p /home/user/backup_repo
    cd /home/user/backup_repo
    git init
    git config user.email "admin@example.com"
    git config user.name "Admin"

    cat << 'EOF' > backup_manager.sh
#!/bin/bash
API_KEY="sk_live_8f7d6c5b4a392817"
total_bytes=0
i=0
nodes=("8000000000000000000" "2000000000000000000")
while [ $i -lt ${#nodes[@]} ]; do
    ((total_bytes += ${nodes[$i]}))
    ((i++))
done
echo "Total bytes: $total_bytes"
EOF
    chmod +x backup_manager.sh

    git add backup_manager.sh
    git commit -m "Initial commit with backup manager"

    cat << 'EOF' > backup_manager.sh
#!/bin/bash
total_bytes=0
i=0
nodes=("8000000000000000000" "2000000000000000000")
while [ $i -lt ${#nodes[@]} ]; do
    ((total_bytes += ${nodes[$i]}))
done
echo "Total bytes: $total_bytes"
EOF

    git add backup_manager.sh
    git commit -m "Remove API key and refactor loop"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
