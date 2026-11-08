#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/pcap_summary.log
session_id bytes start_time end_time
S1 1000 100 105
S2 2500 110 115
S3 5000 120 120
S4 3000 130 140
S5 8000 150 170
S6 0 180 180
EOF

cat << 'EOF' > /home/user/network_analyzer.sh
#!/bin/bash

exec 2> /home/user/trace.log

total_throughput=0

while read -r sid bytes start end; do
    if [[ "$sid" == "session_id" ]]; then continue; fi
    duration=$(( end - start ))

    # Buggy formula: division by zero when start == end
    throughput=$(( bytes / duration ))

    total_throughput=$(( total_throughput + throughput ))
done < /home/user/pcap_summary.log

echo "$total_throughput" > /home/user/result.txt
EOF

chmod +x /home/user/network_analyzer.sh
/home/user/network_analyzer.sh || true

chmod -R 777 /home/user
