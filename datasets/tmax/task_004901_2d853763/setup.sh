#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/pcap_logs.csv
id,timestamp,bytes
1,2024-01-30T14:22:00Z,500
2,2024-01-30T15:22:00Z,600
3,2024-01-31T23:30:00Z,700
4,2024-02-01T10:00:00Z,800
5,2024-02-29T18:15:00Z,900
EOF

    cat << 'EOF' > /home/user/process_pcap_logs.py
#!/usr/bin/env python3
import csv
import datetime
import json
import sys

def get_next_midnight(iso_timestamp):
    # Parse UTC timestamp
    dt = datetime.datetime.fromisoformat(iso_timestamp.replace('Z', '+00:00'))

    current = dt
    # BUG: Naive day increment causes an infinite loop at the end of a month
    target_day = dt.day + 1 

    # Loop until we reach the target day
    loop_count = 0
    while current.day != target_day:
        current += datetime.timedelta(hours=1)
        loop_count += 1
        if loop_count > 1000:
            # Prevent CI runner from completely freezing if unhandled, 
            # but mimic a hang by exiting with a generic error
            print("Error: Hang detected processing " + iso_timestamp)
            sys.exit(1)

    # Return next midnight
    return current.replace(minute=0, second=0, microsecond=0).isoformat()

def main():
    results = {}
    with open('/home/user/pcap_logs.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            print(f"Processing packet ID {row['id']} at {row['timestamp']}")
            next_mid = get_next_midnight(row['timestamp'])
            results[next_mid] = results.get(next_mid, 0) + 1

    with open('/home/user/binned_stats.json', 'w') as f:
        json.dump(results, f, indent=4)

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/process_pcap_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
