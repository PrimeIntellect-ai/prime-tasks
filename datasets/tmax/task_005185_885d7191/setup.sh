#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip logrotate
    pip3 install pytest

    mkdir -p /home/user/edge_storage/logs
    mkdir -p /home/user/bin

    cat << 'EOF' > /home/user/bin/mock_sendmail
#!/bin/bash
cat >> /home/user/mail_outbox.log
echo "---MAIL BOUNDARY---" >> /home/user/mail_outbox.log
EOF
    chmod +x /home/user/bin/mock_sendmail

    head -c 1M </dev/urandom > /home/user/edge_storage/logs/sensor1.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
