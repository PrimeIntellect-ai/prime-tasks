#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tcpdump socat bc gawk
pip3 install pytest scapy

useradd -m -s /bin/bash user || true

mkdir -p /app/bash-metrics-daemon-1.0
mkdir -p /home/user/ticket

cat << 'EOF' > /app/bash-metrics-daemon-1.0/server.sh
#!/bin/bash

handle_client() {
    read -r auth_line
    if [[ "$auth_line" == "AUTH x-daemon-token-99" ]]; then
        echo "OK"
    else
        echo "ERROR: UNAUTHORIZED"
        exit 1
    fi

    while read -r line; do
        if [[ -z "$line" ]]; then continue; fi

        # Parse command
        cmd=$(echo "$line" | awk '{print $1}')

        if [[ "$cmd" == "METRIC" ]]; then
            # Extract values
            values=($(echo "$line" | cut -d' ' -f3-))
            sum=0
            count=${#values[@]}

            for v in "${values[@]}"; do
                sum=$(echo "$sum + $v" | bc)
            done

            avg=$(echo "$sum / $count" | bc)
            echo "AVG: $avg"
        fi
    done
}

export -f handle_client
socat TCP-LISTEN:9090,reuseaddr,fork EXEC:"bash -c handle_client"
EOF
chmod +x /app/bash-metrics-daemon-1.0/server.sh

python3 -c "
from scapy.all import *
pkts = []
eth = Ether(dst='00:00:00:00:00:00', src='00:00:00:00:00:00')
ip = IP(src='127.0.0.1', dst='127.0.0.1')
tcp = TCP(sport=12345, dport=9090, flags='PA')

pkts.append(eth/ip/tcp/Raw(load='AUTH x-daemon-token-99\n'))
pkts.append(eth/ip/tcp/Raw(load='METRIC CPU 100 200 NaN 300\n'))
wrpcap('/home/user/ticket/crash.pcap', pkts)
"

chown -R user:user /app/bash-metrics-daemon-1.0
chown -R user:user /home/user/ticket
chmod -R 777 /home/user
