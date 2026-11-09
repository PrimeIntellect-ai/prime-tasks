#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_data.csv
Timestamp,CustomerName,FeedbackText,PurchaseAmount
1620000005,Charlie,Hello 世界,20.00
1620000001,Bob,👍,5.00
1620000003,Diana,Hola,10.00
1620000004,Eve,😊😊,50.00
1620000002,Alice,Great!,15.50
EOF
    chmod 644 /home/user/raw_data.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
