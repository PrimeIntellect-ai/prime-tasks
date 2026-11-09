#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/system /home/user/config /home/user/bin /home/user/iot_storage /mnt/iot_data

    cat << 'EOF' > /home/user/system/fstab.iot
/dev/sda1 / ext4 defaults 1 1
/home/user/iot_storage /mnt/iot_data ext4 defaults 0 0
EOF

    cat << 'EOF' > /home/user/config/mail.conf
SMTP_HOST=192.168.1.100
SMTP_PORT=25
EOF

    cat << 'EOF' > /home/user/bin/smtp_edge.py
import socket, os, time
conf = {}
with open("/home/user/config/mail.conf") as f:
    for line in f:
        k, v = line.strip().split('=')
        conf[k] = v

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind((conf['SMTP_HOST'], int(conf['SMTP_PORT'])))
s.listen(1)
print(f"SMTP listening on {conf['SMTP_HOST']}:{conf['SMTP_PORT']}")
try:
    while True:
        conn, addr = s.accept()
        data = conn.recv(1024)
        with open("/home/user/mail_received.log", "a") as log:
            log.write(data.decode())
        conn.close()
except KeyboardInterrupt:
    pass
EOF

    cat << 'EOF' > /home/user/bin/sensor_app.sh
#!/bin/bash
while true; do
    sleep 2
done
EOF

    chmod +x /home/user/bin/sensor_app.sh
    chown -R user:user /home/user/*
    chmod -R 777 /home/user
