#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/service_repo/data
    cd /home/user/service_repo

    touch "data/normal_file.txt"
    touch "data/report 2023.dat"
    touch "data/critical backup.tar.gz"

    cat << 'EOF' > scan.sh
#!/bin/bash

# Buggy loop that breaks on spaces
for file in $(ls data/); do
    if [ -f "data/$file" ]; then
        echo "Processing $file"
        # Simulate processing
        sleep 0.1
    else
        echo "Error: data/$file not found. Spawning error handler."
        # In a real scenario, this leaked runaway background processes
    fi
done
EOF
    chmod +x scan.sh

    dd if=/dev/urandom of=crash_heap.dmp bs=1K count=10 2>/dev/null
    echo "[FATAL] File parse error on: critical" >> crash_heap.dmp
    dd if=/dev/urandom bs=1K count=5 >> crash_heap.dmp 2>/dev/null

    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > config.cfg
HOST=localhost
PORT=8080
EOF
    git add config.cfg scan.sh
    git commit -m "Initial commit"

    echo "DEBUG_TOKEN=a1b2c3d4-8f9e-4a5b-9c8d-7e6f5a4b3c2d" >> config.cfg
    git add config.cfg
    git commit -m "Add debug token for testing"

    sed -i '/DEBUG_TOKEN/d' config.cfg
    git add config.cfg
    git commit -m "Remove hardcoded debug token"

    chown -R user:user /home/user
    chmod -R 777 /home/user
