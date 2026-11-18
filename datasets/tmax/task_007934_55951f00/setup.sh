#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bin
    cat << 'EOF' > /home/user/bin/cloud-cost-cli
#!/bin/bash
echo "service,cost"
echo "ec2,145.50"
echo "s3,12.00"
echo "rds,89.25"
EOF
    chmod +x /home/user/bin/cloud-cost-cli

    cat << 'EOF' > /home/user/cost-analyzer.sh
#!/bin/bash
mkdir -p /home/user/reports
data=$(cloud-cost-cli)
total=$(echo "$data" | awk -F',' 'NR>1 {sum+=$2} END {print sum}')
echo "Total Cost: \$$total" > /home/user/reports/daily_cost.log
EOF
    chmod +x /home/user/cost-analyzer.sh

    chmod -R 777 /home/user
