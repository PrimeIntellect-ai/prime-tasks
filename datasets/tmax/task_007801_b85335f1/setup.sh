#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd cron curl
    pip3 install pytest

    mkdir -p /home/user/migration_data
    dd if=/dev/zero of=/home/user/migration_data/dummy_data.bin bs=1M count=2

    cat << 'EOF' > /home/user/fetcher.sh
#!/bin/bash
# Simulates a slow-starting network service
sleep 3
python3 -m http.server 8888 --bind 127.0.0.1 >/dev/null 2>&1 &
SRV_PID=$!
echo $SRV_PID > /tmp/fetcher_internal.pid
wait
EOF
    chmod +x /home/user/fetcher.sh

    cat << 'EOF' > /home/user/processor.sh
#!/bin/bash
# Fails if port 8888 is not open yet
if ! nc -z 127.0.0.1 8888; then
    echo "FAILED: Port not open" > /home/user/pipeline_status.log
    exit 1
fi
echo "SUCCESS: Processor connected" > /home/user/pipeline_status.log
sleep 60
EOF
    chmod +x /home/user/processor.sh

    cat << 'EOF' > /home/user/start_pipeline.sh
#!/bin/bash
/home/user/fetcher.sh &
/home/user/processor.sh &
EOF
    chmod +x /home/user/start_pipeline.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
