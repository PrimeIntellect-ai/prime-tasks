#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incident

    cat << 'EOF' > /home/user/incident/app.log
2023-10-27 14:32:01 INFO Starting risk evaluation batch...
2023-10-27 14:32:05 INFO Processing batch ID: 89912
2023-10-27 14:32:15 ERROR Worker thread crashed!
Traceback (most recent call last):
  File "risk_eval.py", line 45, in evaluate_risk
    risk_score = (purchases * 100) / (account_age_days - 30)
ZeroDivisionError: division by zero
EOF

    head -c 2048 /dev/urandom > /home/user/incident/crash.dmp
    echo 'CURRENT_RECORD_CTX: {"user_id": "U-4091A", "purchases": 12, "account_age_days": 30, "status": "active"}' >> /home/user/incident/crash.dmp
    head -c 1024 /dev/urandom >> /home/user/incident/crash.dmp

    chown -R user:user /home/user/incident
    chmod -R 777 /home/user
