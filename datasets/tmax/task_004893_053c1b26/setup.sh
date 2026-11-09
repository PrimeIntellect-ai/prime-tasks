#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/config_tracker.ini
[device_alpha]
path = /home/user/logs/dev_a.xml
format = xml
encoding = iso-8859-1

[device_beta]
path = /home/user/logs/dev_b.csv
format = csv
encoding = utf-16le

[device_gamma]
path = /home/user/logs/dev_c.json
format = json
encoding = utf-8
EOF

    python3 -c '
xml_content = """<?xml version="1.0" encoding="ISO-8859-1"?>
<log>
  <update><param>network_speed</param><value>1000</value><time>10</time></update>
  <update><param>duplex</param><value>half</value><time>5</time></update>
  <update><param>network_speed</param><value>10000</value><time>25</time></update>
  <update><param>mtu</param><value>1500</value><time>12</time></update>
  <update><param>duplex</param><value>full</value><time>20</time></update>
</log>
"""
with open("/home/user/logs/dev_a.xml", "wb") as f:
    f.write(xml_content.encode("iso-8859-1"))
'

    python3 -c '
csv_content = """parameter,value,timestamp
timeout,30,100
retries,3,105
timeout,60,110
mode,active,90
retries,5,102
"""
with open("/home/user/logs/dev_b.csv", "wb") as f:
    f.write(csv_content.encode("utf-16le"))
'

    cat << 'EOF' > /home/user/logs/dev_c.json
[
  {"p": "power_limit", "v": "150W", "t": 1000},
  {"p": "fan_curve", "v": "aggressive", "t": 1005},
  {"p": "power_limit", "v": "200W", "t": 1010},
  {"p": "led_mode", "v": "breathing", "t": 999}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
