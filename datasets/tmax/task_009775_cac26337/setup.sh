#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ iproute2 procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/routes.txt
10.0.0.0/24 dev eth0 proto kernel scope link src 10.0.0.5
192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.10
default via 10.0.0.1 dev eth0 proto dhcp metric 100
EOF

    echo 'nohup python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.bind(('\'127.0.0.1\'', 8888)); s.listen(1); s.accept()" >/dev/null 2>&1 &' >> /home/user/.bashrc
    echo 'nohup python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.bind(('\'127.0.0.1\'', 8888)); s.listen(1); s.accept()" >/dev/null 2>&1 &' >> /root/.bashrc

    chmod -R 777 /home/user
