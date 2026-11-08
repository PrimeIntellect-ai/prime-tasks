#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat tcpdump
    pip3 install pytest scapy

    mkdir -p /app

    cat << 'EOF' > /app/ingest_service.sh
#!/bin/bash
socat TCP-LISTEN:8000,bind=127.0.0.1,reuseaddr,fork EXEC:/app/ingest_handler.sh
EOF

    cat << 'EOF' > /app/ingest_handler.sh
#!/bin/bash
read -r line
# Forward to DB service
echo "$line $(date +%s)" | socat - TCP:127.0.0.1:8001
EOF

    cat << 'EOF' > /app/db_service.sh
#!/bin/bash
socat TCP-LISTEN:8001,bind=127.0.0.1,reuseaddr,fork EXEC:/app/db_handler.sh
EOF

    cat << 'EOF' > /app/db_handler.sh
#!/bin/bash
read -r cmd app cpu mem ts
# Calculate load (crashes if mem is non-numeric or has \r)
let "load = cpu + mem"
if [ $? -eq 0 ]; then
    echo "OK"
else
    echo "ERROR"
fi
EOF

    chmod +x /app/*.sh

    python3 -c "
from scapy.all import IP, TCP, Raw, wrpcap
packets = []
packets.append(IP(dst='127.0.0.1', src='127.0.0.1')/TCP(dport=8000, sport=12345)/Raw(load=b'METRIC cache 50\r 60\n'))
packets.append(IP(dst='127.0.0.1', src='127.0.0.1')/TCP(dport=8000, sport=12346)/Raw(load=b'METRIC worker 90 NaN\n'))
wrpcap('/app/bottleneck.pcap', packets)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
