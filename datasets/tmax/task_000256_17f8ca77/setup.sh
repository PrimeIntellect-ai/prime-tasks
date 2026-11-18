#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/traffic_logs.csv
id,bytes
1,250
2,300
3,150
4,400
5,50
EOF

    cat << 'EOF' > /home/user/calculate_metrics.sh
#!/bin/bash
total=0
# Skip header
tail -n +2 /home/user/traffic_logs.csv | while IFS=, read -r id bytes; do
    weight=$((bytes * 10000000000000000))
    total=$((total + weight))
done
echo "$total"
EOF
    chmod +x /home/user/calculate_metrics.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
