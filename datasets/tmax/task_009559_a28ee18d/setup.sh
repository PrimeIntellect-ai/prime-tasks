#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    mkdir -p /home/user/logs
    SECRET_TOKEN="TKN_7x9qL2vP"

    cat << 'EOF' > /home/user/simulate_traffic.sh
#!/bin/bash
while true; do
    sleep 60
done
EOF
    chmod +x /home/user/simulate_traffic.sh

    cat << EOF > /home/user/logs/traffic.log
[2023-10-27 10:00:01] Connection received from 192.168.1.45
[2023-10-27 10:00:02] Auth attempt with token TKN_7x9qL2vP - SUCCESS
[2023-10-27 10:00:05] Data packet sent to 10.0.0.254, payload size 1024
[2023-10-27 10:01:00] Admin login from 172.16.0.1 using TKN_7x9qL2vP
[2023-10-27 10:01:15] Ping from 8.8.8.8
[2023-10-27 10:02:00] Invalid token attempt: TKN_WRONG123 from 10.1.2.3
EOF

    # Do not start the process in %post as it will block the build and not persist.
    # Instead, add it to bashrc so it starts when a shell is opened.
    echo "/home/user/simulate_traffic.sh --token=TKN_7x9qL2vP >/dev/null 2>&1 &" >> /root/.bashrc
    echo "/home/user/simulate_traffic.sh --token=TKN_7x9qL2vP >/dev/null 2>&1 &" >> /etc/bash.bashrc

    useradd -m -s /bin/bash user || true
    echo "/home/user/simulate_traffic.sh --token=TKN_7x9qL2vP >/dev/null 2>&1 &" >> /home/user/.bashrc

    chmod -R 777 /home/user
