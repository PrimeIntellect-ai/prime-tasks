#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Create directories
mkdir -p /home/user/data

# Create the metrics file
cat << 'EOF' > /home/user/data/metrics.txt
req_count=150
latency=45
errors=
db_time= 12
cache_hits=NaN
cpu_util=88
EOF

# Create the buggy aggregate.sh script
cat << 'EOF' > /home/user/aggregate.sh
#!/bin/bash
total=0
while read -r line; do
    if [[ -z "$line" || "$line" == \#* ]]; then continue; fi
    key=$(echo "$line" | cut -d= -f1)
    value=$(echo "$line" | cut -d= -f2)
    total=$((total + value))
done < "$1"
echo "Total: $total"
EOF
chmod +x /home/user/aggregate.sh

# Create the cron.log showing the crash
cat << 'EOF' > /home/user/cron.log
[03:00:01] Starting metrics aggregation...
/home/user/aggregate.sh: line 7: total + : syntax error: operand expected (error token is "+ ")
[03:00:02] Pipeline failed with exit code 1.
EOF

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
