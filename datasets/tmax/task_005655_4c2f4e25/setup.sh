#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git tzdata
    pip3 install pytest pytz

    # Create the required data directory and file
    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/input_billing.csv
Timestamp,Service,Region,Cost
2023-10-15T02:00:00Z,Compute,us-east-1,10.00
2023-10-15T03:00:00Z,EgressNetwork,us-east-1,5.50
2023-10-16T01:00:00Z,EgressNetwork,us-west-2,12.25
2023-10-16T04:00:00Z,EgressNetwork,eu-central-1,8.00
2023-10-17T05:00:00Z,Database,us-east-1,100.00
2023-10-17T06:30:00Z,EgressNetwork,ap-northeast-1,20.00
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
