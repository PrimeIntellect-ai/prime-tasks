#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    mkdir -p /home/user/scripts /home/user/monitor /home/user/config

    # Create dummy-service.sh
    cat << 'EOF' > /home/user/scripts/dummy-service.sh
#!/bin/bash
while true; do
    echo "simulated network activity $(date +%s%N)" >> /home/user/monitor/network.log
    sleep 0.1
done
EOF
    chmod +x /home/user/scripts/dummy-service.sh

    # Create initial net-monitor.sh
    cat << 'EOF' > /home/user/scripts/net-monitor.sh
#!/bin/bash
if ! pgrep -f "dummy-service.sh" > /dev/null; then
    echo "Service is down"
else
    echo "Service is up"
fi
EOF
    chmod +x /home/user/scripts/net-monitor.sh

    # Create routes.conf
    cat << 'EOF' > /home/user/config/routes.conf
10.0.0.0 192.168.1.1 eth0
192.168.2.0 0.0.0.0 tun1
INVALID_ROUTE 1.1.1.1 eth0
172.16.0.0 10.0.0.254 wlan0
10.10.10.0 10.10.10.1 tun0
192.168.100.0 192.168.100.1 eth1 extra
EOF

    touch /home/user/monitor/network.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
