#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    cd /home/user

    # 1. Create the local conflicting json module
    cat << 'EOF' > /home/user/json.py
def loads(s):
    raise Exception("Dependency conflict: Local mock json module loaded instead of standard library.")
EOF

    # 2. Create the serialized config
    python3 -c "
import pickle
import base64
config = {'levels': ['ERROR', 'CRITICAL']}
with open('/home/user/config.dat', 'wb') as f:
    f.write(base64.b64encode(pickle.dumps(config)))
"

    # 3. Create the validator module and compile it
    cat << 'EOF' > /home/user/validator.py
def validate(token):
    return token == "DEVOPS_SECRET_2023"
EOF
    python3 -m py_compile /home/user/validator.py
    mv __pycache__/validator.*.pyc /home/user/validator.pyc
    rm -rf __pycache__
    rm /home/user/validator.py

    # 4. Create the log file
    cat << 'EOF' > /home/user/server.log
{"level": "INFO", "msg": "Service started successfully."}
{"level": "ERROR", "msg": "Database connection timeout."}
{"level": "WARNING", "msg": "High memory usage detected."}
{"level": "CRITICAL", "msg": "Application crash out of memory."}
{"level": "ERROR", "msg": "Retry failed for DB connection."}
EOF

    # 5. Create the broken main script
    cat << 'EOF' > /home/user/log_aggregator.py
import sys
import os
import base64
import pickle
import json
import validator

def load_config():
    with open('/home/user/config.dat', 'rb') as f:
        data = f.read()
    # BUG: data is base64 encoded but script tries to unpickle directly
    return pickle.loads(data)

def process_logs(logfile, token):
    assert validator.validate(token), "AssertionError: Invalid security token!"

    config = load_config()
    results = {}
    with open(logfile, 'r') as f:
        for line in f:
            try:
                entry = json.loads(line.strip())
                level = entry.get('level')
                if level in config['levels']:
                    results[level] = results.get(level, 0) + 1
            except Exception as e:
                print(f"Error parsing line: {e}")
    return results

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 log_aggregator.py <logfile> <token>")
        sys.exit(1)

    logfile = sys.argv[1]
    token = sys.argv[2]

    res = process_logs(logfile, token)

    with open('/home/user/summary.txt', 'w') as f:
        f.write(str(res))
    print("Log aggregation successful.")
EOF

    chmod -R 777 /home/user
