#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/observability

    cat << 'EOF' > /home/user/observability/service_b.conf
BIND_IP=127.0.0.1
BIND_PORT=8083
METRICS_PATH=/metrics
EOF

    cat << 'EOF' > /home/user/observability/alert.conf
SMTP_HOST=127.0.0.1
SMTP_PORT=2525
ALERT_EMAIL=admin@local
EOF

    cat << 'EOF' > /home/user/observability/start_service_b.sh
#!/bin/bash
source /home/user/observability/service_b.conf
# Dummy service mimicking python http server
python3 -m http.server $BIND_PORT &
echo $! > /home/user/observability/service_b.pid
EOF
    chmod +x /home/user/observability/start_service_b.sh

    chmod -R 777 /home/user
