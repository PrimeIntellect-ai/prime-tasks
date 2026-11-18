#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/raw_settings.conf
# Deployment configuration for edge node 04
Timezone: Pacific/Fiji
Environment: production
Locale: en_NZ.UTF-8

# Container overrides
RestartPolicy: always
EOF

cat << 'EOF' > /home/user/mock_app.sh
#!/bin/bash
while true; do
    echo "HEARTBEAT - $(date)"
    sleep 1
done
EOF

chmod +x /home/user/mock_app.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
