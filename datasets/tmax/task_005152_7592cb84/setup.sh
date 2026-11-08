#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget python3-dateutil
    pip3 install pytest setuptools_scm

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /app/vendored

    # Download and setup vendored package
    cd /app/vendored
    wget https://files.pythonhosted.org/packages/source/p/python-dateutil/python-dateutil-2.8.2.tar.gz
    tar -xzf python-dateutil-2.8.2.tar.gz
    mv python-dateutil-2.8.2 python-dateutil
    rm python-dateutil-2.8.2.tar.gz

    # Modify setup.py to introduce the bug
    if grep -q "from setuptools import setup" python-dateutil/setup.py; then
        sed -i 's/from setuptools import setup/import non_existent_setuptools_module/g' python-dateutil/setup.py
    else
        sed -i '1s/^/import non_existent_setuptools_module\n/' python-dateutil/setup.py
    fi

    # Create oracle processor
    cat << 'EOF' > /app/oracle_processor.py
#!/usr/bin/env python3
import sys
import csv
import json
import re
from dateutil import parser

def process():
    reader = csv.DictReader(sys.stdin)
    for row in reader:
        raw_time = row.pop('raw_time')
        dt = parser.parse(raw_time)
        dt = dt.replace(second=0, microsecond=0)
        ts_str = dt.strftime("%Y-%m-%dT%H:%M:%SZ")

        sensors = sorted(row.keys())
        for sensor in sensors:
            val_str = row[sensor]
            m = re.match(r'\[VAL:\s*([-\d\.]+)\]\s*\[STATUS:\s*([A-Z]+)\]', val_str)
            if m:
                val = float(m.group(1))
                status = m.group(2)
                if status == "OK" and val >= 0.0:
                    out = {"ts": ts_str, "sensor": sensor, "val": val}
                    print(json.dumps(out))

if __name__ == '__main__':
    process()
EOF
    chmod +x /app/oracle_processor.py

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
