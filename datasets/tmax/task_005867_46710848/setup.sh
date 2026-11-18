#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 make
    pip3 install pytest

    mkdir -p /home/user/waf_project/db
    mkdir -p /home/user/waf_project/downloads

    sqlite3 /home/user/waf_project/db/rules.sqlite "CREATE TABLE core_rules (id INTEGER PRIMARY KEY, pattern TEXT);"
    sqlite3 /home/user/waf_project/db/rules.sqlite "INSERT INTO core_rules (pattern) VALUES ('<script>');"

    cat << 'EOF' > /home/user/waf_project/verify_sigs.py
import sys
import hashlib
import os

if len(sys.argv) != 3:
    print("Usage: python verify_sigs.py <sig_file> <dir>")
    sys.exit(1)

sig_file, target_dir = sys.argv[1], sys.argv[2]

with open(sig_file, 'r') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        filename, expected_hash = line.split(':')
        filepath = os.path.join(target_dir, filename)

        if not os.path.exists(filepath):
            print(f"FAIL: {filename}")
            continue

        sha256 = hashlib.sha256()
        with open(filepath, 'rb') as tf:
            sha256.update(tf.read())

        if sha256.hexdigest() == expected_hash:
            print(f"OK: {filename}")
        else:
            print(f"FAIL: {filename}")
EOF
    chmod +x /home/user/waf_project/verify_sigs.py

    echo "rule1 data" > /home/user/waf_project/downloads/rule1.conf
    echo "rule2 data" > /home/user/waf_project/downloads/rule2.conf

    H1=$(sha256sum /home/user/waf_project/downloads/rule1.conf | awk '{print $1}')
    H2=$(sha256sum /home/user/waf_project/downloads/rule2.conf | awk '{print $1}')

    cat << EOF > /home/user/waf_project/signatures.txt
rule1.conf:$H1
rule2.conf:$H2
EOF

    cat << 'EOF' > /home/user/waf_project/Makefile
clean:
	rm -f build_logs.txt waf_release.tar.gz
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/waf_project
    chmod -R 777 /home/user
