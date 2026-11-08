#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_logs.csv
timestamp,sensor_id,value,message
1000,1,10.00,"Start"
1000,2,20.00,"System init"
1001,1,12.00,"Normal"
1002,1,14.00,"Error:
Line 1
Line 2"
1004,1,10.00,"Recovered"
1004,2,22.00,"Update applied"
EOF

    cat << 'EOF' > /home/user/verify.py
import sys

def generate_golden():
    golden = """timestamp,sensor_id,value,rolling_avg,message
1000,1,10.00,10.00,"Start"
1000,2,20.00,20.00,"System init"
1001,1,12.00,11.00,"Normal"
1001,2,20.00,20.00,""
1002,1,14.00,12.00,"Error: Line 1 Line 2"
1002,2,20.00,20.00,""
1003,1,14.00,13.33,""
1003,2,20.00,20.00,""
1004,1,10.00,12.67,"Recovered"
1004,2,22.00,20.67,"Update applied"
"""
    return golden

try:
    with open('/home/user/processed_logs.csv', 'r') as f:
        actual = f.read()
except FileNotFoundError:
    print("Failed: processed_logs.csv not found")
    sys.exit(1)

expected = generate_golden()

# Compare non-empty lines
actual_lines = [l.strip() for l in actual.strip().split('\n')]
expected_lines = [l.strip() for l in expected.strip().split('\n')]

if actual_lines == expected_lines:
    print("Pass")
    sys.exit(0)
else:
    print("Fail")
    print("Expected:")
    print("\n".join(expected_lines))
    print("Actual:")
    print("\n".join(actual_lines))
    sys.exit(1)
EOF

    chmod -R 777 /home/user
