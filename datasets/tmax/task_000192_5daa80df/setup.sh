#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak systemd
pip3 install pytest

mkdir -p /app
espeak -w /app/outage_alert.wav "Critical failure on primary SMTP. Redirect all emergency mail to backup port eight zero two five."

useradd -m -s /bin/bash user || true

mkdir -p /home/user/bin /home/user/.config/systemd/user
echo "PORT=2525" > /home/user/mailer.conf

cat << 'EOF' > /home/user/bin/check_endpoints.sh
#!/bin/bash
> /home/user/endpoint_status.log
for i in {1..50}; do
    # Simulated check delay
    sleep 0.1
    echo "Endpoint $i: OK" >> /home/user/endpoint_status.log
done
EOF
chmod +x /home/user/bin/check_endpoints.sh

cat << 'EOF' > /home/user/.config/systemd/user/diagnostic-logger.service
[Unit]
Description=Diagnostic Logger
[Service]
ExecStartPre=/bin/bash -c 'mkfifo /home/user/alert_pipe || true'
ExecStart=/bin/bash -c 'tail -f /home/user/alert_pipe'
Restart=on-failure
EOF

cat << 'EOF' > /home/user/.config/systemd/user/alert-sender.service
[Unit]
Description=Alert Sender
# Missing dependency here
[Service]
ExecStart=/bin/bash -c 'echo "Ping" > /home/user/alert_pipe && sleep 1000'
Restart=on-failure
EOF

chown -R user:user /home/user
chmod -R 777 /home/user
