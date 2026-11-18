#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest pandas networkx

    mkdir -p /app

    cat << 'EOF' > /app/.hidden_oracle.py
import sys
import csv

def main():
    if len(sys.argv) != 2:
        sys.exit(1)

    nodes = set()
    out_degrees = {}

    try:
        with open(sys.argv[1], 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                amount = float(row['amount'])
                tx_type = row['transaction_type']
                if amount >= 1000.0 and tx_type != "REFUND":
                    src = row['source_id']
                    tgt = row['target_id']
                    nodes.add(src)
                    nodes.add(tgt)
                    out_degrees[src] = out_degrees.get(src, 0) + 1
                    if tgt not in out_degrees:
                        out_degrees[tgt] = 0
    except Exception:
        pass

    N = len(nodes)
    result = {}
    for node in nodes:
        if N <= 1:
            result[node] = 0.0
        else:
            result[node] = out_degrees.get(node, 0) / (N - 1)

    json_str = "{" + ", ".join(f'"{k}": {result[k]:.4f}' for k in sorted(result.keys())) + "}"
    print(json_str)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /tmp/wrapper.c
#include <stdlib.h>
#include <stdio.h>
int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "python3 /app/.hidden_oracle.py \"%s\"", argv[1]);
    return system(cmd);
}
EOF

    gcc -O2 /tmp/wrapper.c -o /app/analyzer_oracle
    strip /app/analyzer_oracle
    rm /tmp/wrapper.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
