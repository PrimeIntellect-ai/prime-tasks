#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tcpdump
    pip3 install pytest scapy

    # Ensure /usr/sbin/tcpdump exists
    if [ ! -f /usr/sbin/tcpdump ] && [ -f /usr/bin/tcpdump ]; then
        ln -s /usr/bin/tcpdump /usr/sbin/tcpdump
    fi

    mkdir -p /home/user/bad_bin
    cat << 'EOF' > /home/user/bad_bin/tcpdump
#!/bin/bash
# Malicious/conflicting mock that strips the length value but keeps the string
/usr/sbin/tcpdump "$@" | sed -E 's/length [0-9]+/length/g'
EOF
    chmod +x /home/user/bad_bin/tcpdump

    cat << 'EOF' > /home/user/env.sh
export PATH=/home/user/bad_bin:$PATH
export CLEANUP_THRESHOLD=500
EOF

    cat << 'EOF' > /home/user/monitor.sh
#!/bin/bash
source /home/user/env.sh
declare -A PACKET_CACHE
TOTAL_BYTES=0

while read -r line; do
    if echo "$line" | grep -q "IP "; then
        len=$(echo "$line" | grep -oP 'length \K[0-9]+' || echo "")
        src_ip=$(echo "$line" | awk '{print $2}' | cut -d. -f1-4)

        # Cache packet data
        PACKET_CACHE["${#PACKET_CACHE[@]}"]="$line"

        if [[ -n "$len" ]]; then
            TOTAL_BYTES=$((TOTAL_BYTES + len))
        fi

        if (( TOTAL_BYTES > CLEANUP_THRESHOLD )); then
            unset PACKET_CACHE
            declare -A PACKET_CACHE
            TOTAL_BYTES=0
        fi
    fi
done < <(tcpdump -nn -r "$1" 2>/dev/null)
EOF
    chmod +x /home/user/monitor.sh

    python3 -c "
from scapy.all import Ether, IP, TCP, wrpcap
pkts = [
    Ether()/IP(src='10.0.0.5', dst='192.168.1.1')/TCP(sport=1234, dport=80)/('X'*46),
    Ether()/IP(src='10.0.0.5', dst='192.168.1.1')/TCP(sport=1234, dport=80)/('X'*96),
    Ether()/IP(src='172.16.0.2', dst='192.168.1.1')/TCP(sport=4321, dport=80)/('X'*146),
    Ether()/IP(src='10.0.0.5', dst='192.168.1.1')/TCP(sport=1234, dport=80)/('X'*10),
]
wrpcap('/home/user/traffic.pcap', pkts)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
