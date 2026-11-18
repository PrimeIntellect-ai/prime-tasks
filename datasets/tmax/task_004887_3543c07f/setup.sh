#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import os

a_csv = """ts_iso,machine_id,cpu_temp
2023-11-01T14:30:01.450Z,m1,45.5
2023-11-01T14:30:01.900Z,m1,46.5
2023-11-01T14:30:02.100Z,m2,50.0
2023-11-01 14:30:02Z,m2,99.9
invalid_time_string,m1,0.0
2023-11-01T14:30:03.000Z,m1,47.0
"""

b_csv = """ts_unix_ms,machine_id,ram_usage
1698849001100,m1,60.0
1698849001950,m1,62.0
1698849003500,m3,80.0
"""

with open('/home/user/telemetry_a.csv', 'w') as f:
    f.write(a_csv)

with open('/home/user/telemetry_b.csv', 'w') as f:
    f.write(b_csv)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
