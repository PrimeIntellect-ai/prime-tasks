#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_telemetry.csv
1600000000,US,100.0,System OK
1600000045,US,120.0,
1600000130,US,200.0,Fehler
1600000320,US,150.0,タイムアウト
1600000350,US,160.0,
1600000060,JP,300.0,エラー
1600000180,JP,320.0,
EOF

    cat << 'EOF' > /home/user/expected_telemetry.csv
1600000060,JP,300.00,300.00,3
1600000120,JP,300.00,300.00,0
1600000180,JP,320.00,306.67,0
1600000000,US,110.00,110.00,9
1600000060,US,110.00,110.00,0
1600000120,US,200.00,140.00,6
1600000180,US,200.00,155.00,0
1600000240,US,200.00,164.00,0
1600000300,US,155.00,173.00,5
EOF

    cat << 'EOF' > /tmp/verify.py
import sys

def load_csv(path):
    with open(path, 'r', encoding='utf-8') as f:
        return [line.strip() for line in f if line.strip()]

try:
    expected = load_csv('/home/user/expected_telemetry.csv')
    actual = load_csv('/home/user/processed_telemetry.csv')

    if len(expected) != len(actual):
        print("Row count mismatch")
        sys.exit(1)

    for i, (e, a) in enumerate(zip(expected, actual)):
        if e != a:
            print(f"Mismatch at row {i+1}:\nExpected: {e}\nActual:   {a}")
            sys.exit(1)

    print("Success")
    sys.exit(0)
except Exception as e:
    print(f"Error checking solution: {e}")
    sys.exit(1)
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
