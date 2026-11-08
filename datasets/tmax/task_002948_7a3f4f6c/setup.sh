#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/analytics.log
[2023-11-01 12:00:00] INFO Job 99 completed successfully. Mean: 10.5, Variance: 2.1
[2023-11-01 12:00:05] ERROR Job 101 failed. Traceback (most recent call last):
  File "analytics.py", line 42, in calculate_variance
    raise Exception(f"Negative variance calculated: {var}")
Exception: Negative variance calculated: -0.00390625. Inputs: 100000000.1,100000000.2,100000000.3,100000000.4,100000000.5
[2023-11-01 12:00:10] INFO Job 102 completed successfully. Mean: 42.0, Variance: 1.0
[2023-11-01 12:00:15] ERROR Job 105 failed. Traceback (most recent call last):
  File "analytics.py", line 42, in calculate_variance
    raise Exception(f"Negative variance calculated: {var}")
Exception: Negative variance calculated: -0.015625. Inputs: 500000000.01,500000000.02,500000000.03
[2023-11-01 12:00:20] INFO Job 106 completed successfully. Mean: 5.5, Variance: 0.5
[2023-11-01 12:00:25] ERROR Job 110 failed. Traceback (most recent call last):
  File "analytics.py", line 42, in calculate_variance
    raise Exception(f"Negative variance calculated: {var}")
Exception: Negative variance calculated: -0.0078125. Inputs: 999999999.01,999999999.03,999999999.05,999999999.07
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
