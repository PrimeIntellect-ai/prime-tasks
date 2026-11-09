#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
data = """date,missing_key,count
2023-10-01,error.network_timeout,5
2023-10-01,ui.button.save,10
2023-10-03,error.network_timeout,2
2023-10-05,ui.menu.file,4
2023-10-06,error.network_timeout,8
2023-10-07,error.network_timeout,1
"""
with open('/home/user/loc_telemetry.csv', 'w', encoding='utf-16le') as f:
    f.write(data)
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
