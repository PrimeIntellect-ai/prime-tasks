#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip logrotate iproute2 net-tools
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/net_config.ini
[eth0]
address=10.0.0.5
netmask=255.255.255.0
gateway=10.0.0.1

[eth1]
address=192.168.100.2
netmask=255.255.255.0

[wlan0]
address=172.16.0.2
gateway=172.16.0.1
EOF

cat << 'EOF' > /home/user/collect.sh
#!/bin/bash
mkdir -p "$HOME/logs"
echo "Telemetry collected at $(date)" >> "$HOME/logs/telemetry.log"
# dummy network command to test path
ip link show >/dev/null 2>&1 || ifconfig >/dev/null 2>&1 || echo "Network command failed" >> "$HOME/logs/telemetry.log"
EOF
chmod +x /home/user/collect.sh

cat << 'EOF' > /home/user/run_telemetry.sh
#!/bin/bash
export PATH="/usr/bin:/bin"
export HOME="/tmp"

/home/user/collect.sh
EOF
chmod +x /home/user/run_telemetry.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
