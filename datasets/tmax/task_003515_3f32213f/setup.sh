#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo imagemagick tesseract-ocr libtesseract-dev
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /app

    # Generate policy image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'INTERMEDIATE_HUB_PENALTY=25'" /app/policy.png

    # Setup script to generate CSVs and oracle
    cat << 'EOF' > /app/setup.sh
#!/bin/bash
python3 -c "
import csv, random
random.seed(42)
hubs = list(range(1, 51))
with open('/home/user/data/hubs.csv', 'w') as f:
    f.write('hub_id,hub_name,region\n')
    for h in hubs: f.write(f'{h},Hub_{h},Region_{h%5}\n')

with open('/home/user/data/routes.csv', 'w') as f:
    f.write('src_hub_id,dst_hub_id,base_distance\n')
    for u in hubs:
        for v in random.sample(hubs, 5):
            if u != v:
                f.write(f'{u},{v},{random.randint(10, 100)}\n')

with open('/home/user/data/cargo.csv', 'w') as f:
    f.write('src_hub_id,dst_hub_id,shipment_id,tonnage\n')
    for i in range(200):
        u = random.choice(hubs)
        v = random.choice(hubs)
        f.write(f'{u},{v},{i},{random.uniform(1.0, 10.0):.2f}\n')
"

cat << 'ORACLE' > /app/oracle_route_engine
#!/usr/bin/env python3
import sys
import csv
import heapq

penalty = 25

hubs = set()
with open('/home/user/data/hubs.csv') as f:
    reader = csv.reader(f)
    next(reader, None)
    for row in reader:
        if row: hubs.add(int(row[0]))

adj = {h: [] for h in hubs}
with open('/home/user/data/routes.csv') as f:
    reader = csv.reader(f)
    next(reader, None)
    for row in reader:
        if row:
            u, v, d = int(row[0]), int(row[1]), int(row[2])
            if u in adj: adj[u].append((v, d))

cargo = {}
with open('/home/user/data/cargo.csv') as f:
    reader = csv.reader(f)
    next(reader, None)
    for row in reader:
        if row:
            u, v, t = int(row[0]), int(row[1]), float(row[3])
            cargo[(u, v)] = cargo.get((u, v), 0.0) + t

for line in sys.stdin:
    line = line.strip()
    if not line: continue
    parts = line.split(',')
    if len(parts) != 2: continue
    start, end = int(parts[0]), int(parts[1])

    dists = {start: 0}
    paths = {start: [start]}
    pq = [(0, start)]

    while pq:
        d, u = heapq.heappop(pq)
        if d > dists.get(u, float('inf')): continue
        if u == end: break
        for v, weight in adj.get(u, []):
            cost = weight
            if u != start:
                cost += penalty
            if dists.get(v, float('inf')) > d + cost:
                dists[v] = d + cost
                paths[v] = paths[u] + [v]
                heapq.heappush(pq, (dists[v], v))

    if end in dists:
        p = paths[end]
        dist = dists[end]
        tot_cargo = 0.0
        for i in range(len(p)-1):
            tot_cargo += cargo.get((p[i], p[i+1]), 0.0)
        p_str = "-".join(map(str, p))
        print(f"Query: {start}->{end} | Path: {p_str} | Dist: {dist} | Cargo: {tot_cargo:.1f}")
    else:
        print(f"Query: {start}->{end} | Path: NONE | Dist: 0 | Cargo: 0.0")
ORACLE

chmod +x /app/oracle_route_engine
EOF

    chmod +x /app/setup.sh
    /app/setup.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
