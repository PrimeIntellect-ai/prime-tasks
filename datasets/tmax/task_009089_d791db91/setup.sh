#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import csv

os.makedirs('/home/user', exist_ok=True)

csv_path = '/home/user/config_changes.csv'

# Data with embedded newlines, quotes, and commas
data = [
    ["Timestamp", "ServerID", "Category", "ConfigKey", "OldValue", "NewValue", "ChangeReason"],
    ["2023-10-01T10:00:00Z", "srv-01", "Network", "IP_Routes", "192.168.1.0/24 gw 10.0.0.1", "192.168.1.0/24 gw 10.0.0.2", "Updated default route"],
    ["2023-10-01T10:05:00Z", "srv-02", "Database", "pg_hba.conf", "host all all 0.0.0.0/0 md5", "host all all 0.0.0.0/0 md5\nhost rep all 10.0.0.0/8 md5", "Added replication\nrule for subnet"],
    ["2023-10-01T10:10:00Z", "srv-01", "Network", "DNS", "8.8.8.8, 8.8.4.4", "1.1.1.1, 1.0.0.1", "Switched to Cloudflare,\nremoved Google"],
    ["2023-10-01T10:15:00Z", "srv-03", "Database", "max_connections", "100", "500", "Increased for load"],
    ["2023-10-01T10:20:00Z", "srv-04", "AppServer", "jvm_args", "-Xmx2G -Xms2G", "-Xmx4G -Xms4G\n-XX:+UseG1GC", "Memory upgrade\nand \"GC\" tuning"],
    ["2023-10-01T10:25:00Z", "srv-02", "Database", "shared_buffers", "1GB", "2GB", "Performance tuning"],
    ["2023-10-01T10:30:00Z", "srv-01", "Network", "Firewall", "allow 22\nallow 80", "allow 22\nallow 80\nallow 443", "Open HTTPS port"]
]

with open(csv_path, 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
    writer.writerows(data)

with open('/home/user/category_stats_expected.csv', 'w') as f:
    f.write("AppServer,15.00\n")
    f.write("Database,10.00\n")
    f.write("Network,9.00\n")

with open('/home/user/top_changes_expected.csv', 'w') as f:
    f.write("AppServer,2023-10-01T10:20:00Z,srv-04,jvm_args,15\n")
    f.write("Database,2023-10-01T10:05:00Z,srv-02,pg_hba.conf,28\n")
    f.write("Network,2023-10-01T10:10:00Z,srv-01,DNS,16\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
