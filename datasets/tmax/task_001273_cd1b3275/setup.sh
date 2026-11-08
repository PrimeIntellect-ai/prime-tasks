#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app

    # Generate audio file
    espeak -w /app/intercept.wav "Time 1600000010, alpha 15.0, beta 9.5. Time 1600000015, alpha 20.0."

    # Create historical logs
    cat << 'EOF' > /app/historical_logs.jsonl
{"time": 1600000000, "sensors": {"alpha": 10.0, "beta": 5.0}}
{"time": 1600000005, "sensors": {"beta": 7.0}}
EOF

    # Create oracle processor
    cat << 'EOF' > /app/oracle_processor
#!/usr/bin/env python3
import sys
import json
from collections import defaultdict

def process():
    data = defaultdict(list)
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        try:
            row = json.loads(line)
            t = int(row['time'])
            for s, v in row.get('sensors', {}).items():
                data[s].append((t, float(v)))
        except:
            pass

    print("sensor,time,value")
    for s in sorted(data.keys()):
        pts = data[s]
        t_dict = defaultdict(list)
        for t, v in pts:
            t_dict[t].append(v)

        agg_pts = sorted([(t, sum(vs)/len(vs)) for t, vs in t_dict.items()])
        if not agg_pts: continue

        min_t = agg_pts[0][0]
        max_t = agg_pts[-1][0]

        idx = 0
        for t in range(min_t, max_t + 1):
            if t == agg_pts[idx][0]:
                val = agg_pts[idx][1]
                print(f"{s},{t},{val:.4f}")
            elif idx + 1 < len(agg_pts):
                while idx + 1 < len(agg_pts) and agg_pts[idx+1][0] < t:
                    idx += 1
                if t == agg_pts[idx][0]:
                    val = agg_pts[idx][1]
                    print(f"{s},{t},{val:.4f}")
                elif t == agg_pts[idx+1][0]:
                    val = agg_pts[idx+1][1]
                    print(f"{s},{t},{val:.4f}")
                else:
                    t0, v0 = agg_pts[idx]
                    t1, v1 = agg_pts[idx+1]
                    val = v0 + (v1 - v0) * (t - t0) / (t1 - t0)
                    print(f"{s},{t},{val:.4f}")

if __name__ == '__main__':
    process()
EOF
    chmod +x /app/oracle_processor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
