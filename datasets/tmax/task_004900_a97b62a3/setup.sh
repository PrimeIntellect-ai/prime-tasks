#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Generate the video with ffmpeg using drawtext
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=10 \
        -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='%{expr\:101+trunc(t)}\,R%{expr\:1+trunc(t)}':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2" \
        -c:v libx264 -pix_fmt yuv420p -y /app/historical_locks.mp4

    # Create the oracle
    cat << 'EOF' > /app/oracle_etl
#!/usr/bin/env python3
import sys
import csv
import json

def main():
    if len(sys.argv) < 2:
        return

    holds = {}
    waits = {}

    for i in range(10):
        t = 101 + i
        r = f"R{i+1}"
        holds[r] = t

    with open(sys.argv[1], 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if not row: continue
            ts, tid, rid, action = row
            ts = int(ts)
            tid = int(tid)

            if action == 'REQUEST':
                if rid not in holds:
                    holds[rid] = tid
                else:
                    waits[tid] = (rid, ts)
            elif action == 'RELEASE':
                if holds.get(rid) == tid:
                    del holds[rid]
                    waiting_for_r = [(t, wts) for t, (wr, wts) in waits.items() if wr == rid]
                    if waiting_for_r:
                        waiting_for_r.sort(key=lambda x: x[1])
                        next_t = waiting_for_r[0][0]
                        holds[rid] = next_t
                        del waits[next_t]

    graph = {}
    for t, (r, ts) in waits.items():
        if r in holds:
            graph[t] = holds[r]

    def find_cycles():
        visited = set()
        cycles = []
        for start_node in graph:
            if start_node in visited: continue
            path = []
            curr = start_node
            while curr in graph:
                path.append(curr)
                visited.add(curr)
                curr = graph[curr]
                if curr in path:
                    idx = path.index(curr)
                    cycle = sorted(path[idx:])
                    if cycle not in cycles:
                        cycles.append(cycle)
                    break
        return cycles

    deadlocks = find_cycles()
    deadlocks.sort()

    longest_wait = None
    if waits:
        longest_wait = min(waits.items(), key=lambda x: x[1][1])[0]

    print(json.dumps({"deadlocks": deadlocks, "longest_wait": longest_wait}))

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_etl

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
