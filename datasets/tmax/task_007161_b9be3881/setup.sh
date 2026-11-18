#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_logs
    mkdir -p /home/user/secure_logs

    cat << 'EOF' > /home/user/raw_logs/payment.log
2023-10-01T12:00:01 [INFO] action="login" user="alice"
2023-10-01T12:00:05 [ERROR] action="checkout" tx_id="TX-9912" reason="insufficient_funds"
2023-10-01T12:01:00 [WARN] action="checkout" tx_id="TX-9913" reason="timeout_retry"
2023-10-01T12:02:15 [ERROR] action="checkout" tx_id="TX-9914" reason="network_failure" module="gateway"
2023-10-01T12:05:00 [ERROR] action="refund" tx_id="TX-9910" reason="invalid_account"
2023-10-01T12:06:22 [ERROR] action="checkout" tx_id="TX-9915" reason="card_expired"
EOF

    chmod -R 777 /home/user
