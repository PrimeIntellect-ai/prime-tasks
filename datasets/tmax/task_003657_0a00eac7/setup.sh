#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/.hidden_validator.py
import sys
import csv
from collections import defaultdict

def validate(file):
    try:
        with open(file, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
    except:
        return False

    children = defaultdict(list)
    nodes = {}
    for r in rows:
        aid = r['account_id']
        pid = r['parent_account_id']
        bal = float(r['balance'])
        typ = r['account_type']
        nodes[aid] = {'pid': pid, 'bal': bal, 'typ': typ}
        if pid:
            children[pid].append(aid)

    for pid in children:
        if pid in nodes and nodes[pid]['typ'] == 'Leaf':
            return False

    for aid, data in nodes.items():
        if data['typ'] == 'Summary':
            child_sum = sum(nodes[c]['bal'] for c in children[aid])
            if abs(data['bal'] - child_sum) > 1e-5:
                return False

    visited = set()
    path = set()

    def dfs(node, depth):
        if depth > 7:
            return False
        if node in path:
            return False
        if node in visited:
            return True
        path.add(node)
        for c in children[node]:
            if not dfs(c, depth + 1):
                return False
        path.remove(node)
        visited.add(node)
        return True

    roots = [aid for aid, d in nodes.items() if not d['pid']]
    for r in roots:
        if not dfs(r, 1):
            return False

    if len(visited) != len(nodes):
        return False

    return True

if __name__ == '__main__':
    if validate(sys.argv[1]):
        sys.exit(0)
    sys.exit(1)
EOF

    cat << 'EOF' > /app/val.c
#include <stdlib.h>
#include <stdio.h>
int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "python3 /app/.hidden_validator.py %s", argv[1]);
    return system(cmd) / 256;
}
EOF

    gcc /app/val.c -o /app/legacy_validator
    strip -s /app/legacy_validator
    rm /app/val.c

    cat << 'EOF' > /app/generate.py
import os
import csv

def write_csv(path, rows):
    with open(path, 'w') as f:
        writer = csv.DictWriter(f, fieldnames=['account_id', 'parent_account_id', 'balance', 'account_type'])
        writer.writeheader()
        writer.writerows(rows)

for i in range(50):
    rows = [
        {'account_id': '1', 'parent_account_id': '', 'balance': '100', 'account_type': 'Summary'},
        {'account_id': '2', 'parent_account_id': '1', 'balance': '100', 'account_type': 'Leaf'}
    ]
    write_csv(f'/app/corpus/clean/clean_{i}.csv', rows)

for i in range(50):
    if i % 4 == 0:
        rows = [
            {'account_id': '1', 'parent_account_id': '2', 'balance': '100', 'account_type': 'Summary'},
            {'account_id': '2', 'parent_account_id': '1', 'balance': '100', 'account_type': 'Summary'}
        ]
    elif i % 4 == 1:
        rows = [{'account_id': '1', 'parent_account_id': '', 'balance': '0', 'account_type': 'Summary'}]
        for j in range(2, 10):
            rows.append({'account_id': str(j), 'parent_account_id': str(j-1), 'balance': '0', 'account_type': 'Summary'})
    elif i % 4 == 2:
        rows = [
            {'account_id': '1', 'parent_account_id': '', 'balance': '100', 'account_type': 'Summary'},
            {'account_id': '2', 'parent_account_id': '1', 'balance': '50', 'account_type': 'Leaf'}
        ]
    else:
        rows = [
            {'account_id': '1', 'parent_account_id': '', 'balance': '100', 'account_type': 'Leaf'},
            {'account_id': '2', 'parent_account_id': '1', 'balance': '100', 'account_type': 'Leaf'}
        ]
    write_csv(f'/app/corpus/evil/evil_{i}.csv', rows)
EOF

    python3 /app/generate.py
    rm /app/generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
