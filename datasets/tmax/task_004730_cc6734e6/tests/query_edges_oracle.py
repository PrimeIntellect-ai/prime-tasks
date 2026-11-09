#!/usr/bin/env python3
import sys
import csv

if len(sys.argv) != 2:
    sys.exit(1)
node_id = sys.argv[1]

results = []
try:
    with open('edges.csv', 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if row[0] == node_id:
                results.append((int(row[1]), int(row[2])))
except FileNotFoundError:
    pass

results.sort(key=lambda x: (x[0], x[1]))
for r in results:
    print(f"{r[0]},{r[1]}")
