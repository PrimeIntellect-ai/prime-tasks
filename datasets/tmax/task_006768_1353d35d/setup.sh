#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app
    mkdir -p /home/user/crash_reports

    # 1. Create the buggy Python file
    cat << 'EOF' > /home/user/app/risk_calc.py
import math

def calculate_risk(v_list, w_list):
    """
    Calculates the Risk Index for given V and W value lists.
    """
    if not v_list or not w_list or len(v_list) != len(w_list):
        return 0.0

    numerator = sum(v * w for v, w in zip(v_list, w_list))

    sum_v_sq = sum(v**2 for v in v_list)
    sum_w_sq = sum(w**2 for w in w_list)

    # Bug: missing absolute value, will crash on math.sqrt for negative differences
    denominator_squared = sum_v_sq - sum_w_sq 

    return numerator / math.sqrt(denominator_squared)
EOF

    # 2. Create the transactions.json data
    cat << 'EOF' > /home/user/app/transactions.json
{
  "TXN-ABCD-1234": {
    "v_list": [10, 20, 30],
    "w_list": [5, 10, 15]
  },
  "TXN-EFGH-5678": {
    "v_list": [50, 60],
    "w_list": [20, 30]
  },
  "TXN-KLMN-9382": {
    "v_list": [10, 20, 30],
    "w_list": [15, 25, 35]
  },
  "TXN-WXYZ-9999": {
    "v_list": [100, 200],
    "w_list": [10, 20]
  }
}
EOF

    # 3. Create the binary memory dump with the embedded string
    python3 -c '
import random
with open("/home/user/crash_reports/memdump.dat", "wb") as f:
    f.write(bytes([random.randint(0, 255) for _ in range(1024)]))
    f.write(b"CURRENT_PROCESSING_TXN: TXN-KLMN-9382\x00")
    f.write(bytes([random.randint(0, 255) for _ in range(1024)]))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
