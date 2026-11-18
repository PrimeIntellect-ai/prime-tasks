#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git curl socat
    pip3 install pytest

    mkdir -p /home/user/app_repo
    cd /home/user/app_repo
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    cat << 'EOF' > start_all.sh
#!/bin/bash
cd /home/user/app_repo
source router_config.env
mkdir -p /tmp/service_logs
> /tmp/pids
./router_service.sh > /tmp/service_logs/router.log 2>&1 & echo $! >> /tmp/pids
./processing_worker.sh > /tmp/service_logs/worker.log 2>&1 & echo $! >> /tmp/pids
./logging_service.sh > /tmp/service_logs/logger.log 2>&1 & echo $! >> /tmp/pids
EOF
    chmod +x start_all.sh

    cat << 'EOF' > router_service.sh
#!/bin/bash
socat TCP-LISTEN:8000,reuseaddr,fork EXEC:"curl -s http://localhost:8001/process"
EOF
    chmod +x router_service.sh

    cat << 'EOF' > logging_service.sh
#!/bin/bash
socat TCP-LISTEN:8002,reuseaddr,fork EXEC:"echo logged"
EOF
    chmod +x logging_service.sh

    cat << 'EOF' > processing_worker.sh
#!/bin/bash
socat TCP-LISTEN:8001,reuseaddr,fork EXEC:"echo -e 'HTTP/1.1 200 OK\r\n\r\ndone'"
EOF
    chmod +x processing_worker.sh

    cat << 'EOF' > router_config.env
WORKER_TIMEOUT=200
EOF

    git add .
    git commit -m "Initial commit"

    for i in $(seq 2 142); do
        echo "commit $i" > dummy.txt
        git add dummy.txt
        git commit -m "Commit $i"
    done

    # Commit 143 (bad commit)
    cat << 'EOF' > processing_worker.sh
#!/bin/bash
socat TCP-LISTEN:8001,reuseaddr,fork EXEC:"sleep 3; echo -e 'HTTP/1.1 200 OK\r\n\r\ndone'"
EOF
    chmod +x processing_worker.sh

    cat << 'EOF' > router_config.env
WORKER_TIMEOUT=5000
EOF

    git add processing_worker.sh router_config.env
    git commit -m "Commit 143 - feature update"

    for i in $(seq 144 200); do
        echo "commit $i" > dummy.txt
        git add dummy.txt
        git commit -m "Commit $i"
    done

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
