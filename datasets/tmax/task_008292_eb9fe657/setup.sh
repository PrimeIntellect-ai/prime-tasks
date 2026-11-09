#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tshark sqlite3
    pip3 install pytest scapy pytz

    mkdir -p /home/user/ticket4092

    # Create market_data.db and traffic.pcap
    python3 -c "
import sqlite3
conn = sqlite3.connect('/home/user/ticket4092/market_data.db')
c = conn.cursor()
c.execute('''CREATE TABLE trades (timestamp TEXT, price REAL, volume INTEGER)''')
c.execute(\"INSERT INTO trades VALUES ('2023-10-27T14:15:00Z', 100.0, 10)\")
c.execute(\"INSERT INTO trades VALUES ('2023-10-27T14:45:00Z', 105.0, 20)\")
c.execute(\"INSERT INTO trades VALUES ('2023-10-27T18:15:00Z', 90.0, 100)\")
c.execute(\"INSERT INTO trades VALUES ('2023-10-27T18:45:00Z', 95.0, 200)\")
conn.commit()
conn.close()

from scapy.all import IP, TCP, Raw, wrpcap
pkt = IP(dst='127.0.0.1')/TCP(dport=8080)/Raw(load='GET /vwap?start=2023-10-27T14:00:00Z&end=2023-10-27T15:00:00Z HTTP/1.1\r\nHost: 127.0.0.1:8080\r\n\r\n')
wrpcap('/home/user/ticket4092/traffic.pcap', [pkt])
"

    # Create vwap_service.py
    cat << 'EOF' > /home/user/ticket4092/vwap_service.py
import sqlite3
import datetime
import pytz
from urllib.parse import urlparse, parse_qs

def calculate_vwap(start_str, end_str):
    # THE BUG: Parses as naive datetime, then forcibly localizes to US/Eastern 
    # instead of treating the incoming 'Z' as UTC.
    fmt = "%Y-%m-%dT%H:%M:%SZ"
    start_dt = datetime.datetime.strptime(start_str, fmt)
    end_dt = datetime.datetime.strptime(end_str, fmt)

    eastern = pytz.timezone('US/Eastern')
    start_dt = eastern.localize(start_dt)
    end_dt = eastern.localize(end_dt)

    # Convert to UTC string for DB comparison
    db_start = start_dt.astimezone(pytz.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    db_end = end_dt.astimezone(pytz.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    conn = sqlite3.connect('/home/user/ticket4092/market_data.db')
    cursor = conn.cursor()
    cursor.execute("SELECT price, volume FROM trades WHERE timestamp >= ? AND timestamp <= ?", (db_start, db_end))

    total_value = 0.0
    total_volume = 0
    for price, volume in cursor.fetchall():
        total_value += price * volume
        total_volume += volume

    if total_volume == 0:
        return 0.0
    return total_value / total_volume
EOF

    # Create service.log
    cat << 'EOF' > /home/user/ticket4092/service.log
[INFO] 2023-10-27 15:01:22 - Starting VWAP Server on port 8080
[INFO] 2023-10-27 15:05:10 - Received request: GET /vwap?start=2023-10-27T14:00:00Z&end=2023-10-27T15:00:00Z
[INFO] 2023-10-27 15:05:10 - Querying DB from 2023-10-27T18:00:00Z to 2023-10-27T19:00:00Z
[INFO] 2023-10-27 15:05:10 - Result VWAP: 93.3333
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
