#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/raw_logs
    mkdir -p /home/user/processed_logs

    cat << 'EOF' > /home/user/simulate_writer.sh
#!/bin/bash
# Simulates the racing log writer
cd /home/user/raw_logs

# Log 1
echo "[INFO] System boot" > app.log
echo "[ERROR] Database connection failed
Traceback (most recent call last):
  File \"db.py\", line 12
ConnectionRefusedError" >> app.log
echo "[INFO] Retrying..." >> app.log
mv app.log app.log.1

sleep 1

# Log 2
echo "[DEBUG] Healthcheck ping" > app.log
echo "[ERROR] Out of memory
Allocated: 4GB
Requested: 8GB" >> app.log
echo "[INFO] Cleanup triggered" >> app.log
mv app.log app.log.2

sleep 1

# Log 3
echo "[INFO] Normal operation" > app.log
echo "[WARN] High CPU" >> app.log
echo "[ERROR] Disk full
Path: /var/log
Free: 0 bytes
Please clear space" >> app.log
mv app.log app.log.3
EOF
    chmod +x /home/user/simulate_writer.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
