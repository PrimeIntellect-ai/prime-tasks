#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd gawk sed grep coreutils
    pip3 install pytest

    mkdir -p /app/pipeline

    cat << 'EOF' > /app/pipeline/start.sh
#!/bin/bash
nohup ./ingest.sh > ingest.log 2>&1 &
nohup ./api.sh > api.log 2>&1 &
echo "Services started."
EOF

    cat << 'EOF' > /app/pipeline/ingest.sh
#!/bin/bash
while true; do
  # Read HTTP request
  nc -l -p 8080 -q 1 | grep -v '^HTTP' | grep -v '^Host:' | grep -v '^User-Agent:' | grep -v '^Accept' | grep -v '^Content-' | grep -v '^\s*$' | ./process.sh
done
EOF

    cat << 'EOF' > /app/pipeline/api.sh
#!/bin/bash
# Broken API script
while true; do
  nc -l -p 8081 -q 1 < /tmp/stats.json
done
EOF

    cat << 'EOF' > /app/pipeline/process.sh
#!/bin/bash
# TODO: Implement data cleaning, sorting, and rolling stats logic
EOF

    chmod +x /app/pipeline/*.sh
    chmod -R 777 /app/pipeline

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
