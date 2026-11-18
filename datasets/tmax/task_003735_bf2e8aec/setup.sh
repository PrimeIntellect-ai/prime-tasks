#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk jq
    pip3 install pytest

    mkdir -p /app

    # Create the oracle script
    cat << 'EOF' > /app/oracle_aggregate_graph.py
#!/usr/bin/env python3
import sys
import csv
from collections import defaultdict

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    nodes = {}
    children = defaultdict(list)

    with open(sys.argv[1], 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            nid = int(row['node_id'])
            pid = int(row['parent_id']) if row['parent_id'] and row['parent_id'] != '0' else 0
            val = int(row['metric_value'])
            nodes[nid] = val
            if pid != 0:
                children[pid].append(nid)

    memo = {}
    def get_sum(n):
        if n in memo: return memo[n]
        s = nodes.get(n, 0)
        for c in children[n]:
            s += get_sum(c)
        memo[n] = s
        return s

    print("node_id,total_metric")
    for nid in sorted(nodes.keys()):
        print(f"{nid},{get_sum(nid)}")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_aggregate_graph.py

    # Create subtitles file
    cat << 'EOF' > /tmp/subtitles.srt
1
00:00:00,000 --> 00:00:02,000
node_id,parent_id,metric_value

2
00:00:02,000 --> 00:00:04,000
1,0,100

3
00:00:04,000 --> 00:00:06,000
2,1,50

4
00:00:06,000 --> 00:00:08,000
3,1,20

5
00:00:08,000 --> 00:00:10,000
4,2,10

6
00:00:10,000 --> 00:00:12,000
5,2,5
EOF

    # Generate a blank video with the subtitle track
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=12 -i /tmp/subtitles.srt -c:v libx264 -c:s mov_text -map 0:v -map 1:s /app/incident_log.mp4
    rm /tmp/subtitles.srt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
