#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/build/logs

    cat << 'EOF' > /home/user/build/ingest.py
import sys
import os
import glob
import json

def parse_timestamp(ts):
    # Custom parser expecting YYYY-MM-DDTHH:MM:SS.mmmmmmZ
    ts = ts.strip()
    date_part, time_part = ts.split('T')
    time_part = time_part.rstrip('Z')
    h, m, s_m = time_part.split(':')
    s, frac = s_m.split('.') # BUG: Crashes if there's no '.' in the seconds part
    return date_part, h, m, s, frac

def main():
    if len(sys.argv) != 3:
        print("Usage: ingest.py <log_dir> <out_file>")
        sys.exit(1)

    log_dir = sys.argv[1]
    out_file = sys.argv[2]
    events = []

    for filepath in glob.glob(os.path.join(log_dir, "*.log")):
        with open(filepath) as f:
            for line in f:
                if not line.strip(): continue
                parts = line.split(' | ', 2)
                if len(parts) == 3:
                    svc_name, ts, msg = parts
                    sort_key = parse_timestamp(ts)
                    events.append({
                        'sort_key': sort_key,
                        'service': svc_name.strip(),
                        'timestamp': ts.strip(),
                        'message': msg.strip()
                    })

    events.sort(key=lambda x: x['sort_key'])
    for e in events:
        del e['sort_key']

    with open(out_file, 'w') as f:
        json.dump(events, f, indent=2)

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > /home/user/build/logs/service_a.log
service_a | 2023-10-25T15:30:00.123456Z | Started processing batch A
service_a | 2023-10-25T15:31:00.000000Z | Completed batch A
EOF

    cat << 'EOF' > /home/user/build/logs/service_b.log
service_b | 2023-10-25T15:30:30.500000Z | Received data from upstream
service_b | 2023-10-25T15:31:05Z | Heartbeat ping successful
service_b | 2023-10-25T15:31:10.100000Z | Sent data downstream
EOF

    cat << 'EOF' > /home/user/build/logs/service_c.log
service_c | 2023-10-25T15:29:55.999999Z | Initializing service C workers
service_c | 2023-10-25T15:32:00.000000Z | Shutting down workers
EOF

    chmod -R 777 /home/user
