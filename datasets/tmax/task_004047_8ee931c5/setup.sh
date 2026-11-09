#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest python-dateutil

mkdir -p /app
cat << 'EOF' > /app/.hidden_script.py
import sys
import re
import json
from datetime import datetime
from collections import defaultdict
import dateutil.parser

def parse_date(ts):
    try:
        if ts.isdigit() or (ts.startswith('-') and ts[1:].isdigit()):
            dt = datetime.utcfromtimestamp(int(ts))
        else:
            dt = dateutil.parser.parse(ts)
            if dt.tzinfo is not None:
                dt = dt.astimezone(dateutil.tz.tzutc())
                dt = dt.replace(tzinfo=None)
        return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    except:
        return "1970-01-01T00:00:00Z"

def main():
    history = defaultdict(list)
    pattern = re.compile(r'^\[(.*?)\] User:([a-zA-Z0-9_]+) Action:(.*?) Metric:([0-9]+)$')
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        m = pattern.match(line)
        if not m:
            continue
        ts, user, action, metric = m.groups()

        action = " ".join(action.split()).upper()

        aligned_time = parse_date(ts)
        metric = int(metric)

        user_hist = history[user]
        user_hist.append(metric)
        if len(user_hist) > 3:
            user_hist.pop(0)

        avg = sum(user_hist) // len(user_hist)

        out = {
            "time": aligned_time,
            "user": user,
            "action": action,
            "current_metric": metric,
            "rolling_avg": avg
        }
        print(json.dumps(out, separators=(',', ':')))

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > /app/wrapper.c
#include <stdlib.h>
int main() {
    return system("python3 /app/.hidden_script.py");
}
EOF

gcc -static -o /app/log_processor_legacy /app/wrapper.c
strip -s /app/log_processor_legacy
rm /app/wrapper.c
chmod +x /app/log_processor_legacy

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
