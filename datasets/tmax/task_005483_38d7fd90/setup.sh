#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gzip
    pip3 install pytest

    mkdir -p /home/user/incoming /home/user/processed /home/user/archive

    cat << 'EOF' > /home/user/simulate_incoming.sh
#!/bin/bash
sleep 2

cat << 'LOG' > /home/user/incoming/batch1.log
2023-10-01 10:00:00 | AuthBase | INFO | Login success
2023-10-01 10:00:01 | AuthBase | FATAL | Keymaster disconnected
2023-10-01 10:00:02 | DB_Core | WARN | High latency
LOG

sleep 2

cat << 'LOG' | gzip > /home/user/incoming/batch2.gz
2023-10-01 10:00:03 | DB_Core | FATAL | Table corruption detected
2023-10-01 10:00:04 | Network | FATAL | Socket bind failed
2023-10-01 10:00:05 | AuthBase | INFO | Retry login
LOG

sleep 2

touch /home/user/incoming/EOF.txt
EOF

    chmod +x /home/user/simulate_incoming.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
