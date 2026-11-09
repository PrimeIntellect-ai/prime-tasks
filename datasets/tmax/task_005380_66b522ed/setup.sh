#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/.hidden_impl.py
import sys
import csv
import json
from collections import defaultdict

def main():
    if len(sys.argv) != 3:
        sys.exit(1)

    in_file = sys.argv[1]
    out_file = sys.argv[2]

    data = defaultdict(lambda: defaultdict(list))

    with open(in_file, 'r') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pass
        for row in reader:
            if len(row) < 4:
                continue
            server_id = row[0].strip()
            timestamp_str = row[1].strip()
            metric_name = row[2].strip()
            value_str = row[3].strip()

            if not server_id or not metric_name:
                continue
            try:
                timestamp = int(timestamp_str)
            except ValueError:
                continue
            if timestamp < 0:
                continue

            val = float(value_str) if value_str != "" else None
            data[server_id][metric_name].append((timestamp, val))

    out_data = {}
    for sid in sorted(data.keys()):
        out_data[sid] = {}
        for mname in sorted(data[sid].keys()):
            records = sorted(data[sid][mname], key=lambda x: x[0])

            n = len(records)
            imputed = []
            for i in range(n):
                t, v = records[i]
                if v is None:
                    prev_v, prev_t = None, None
                    for j in range(i-1, -1, -1):
                        if records[j][1] is not None:
                            prev_v, prev_t = records[j][1], records[j][0]
                            break
                    next_v, next_t = None, None
                    for j in range(i+1, n):
                        if records[j][1] is not None:
                            next_v, next_t = records[j][1], records[j][0]
                            break

                    if prev_v is not None and next_v is not None:
                        if next_t == prev_t:
                            v = prev_v
                        else:
                            v = prev_v + (next_v - prev_v) * ((t - prev_t) / (next_t - prev_t))
                    elif prev_v is not None:
                        v = prev_v
                    elif next_v is not None:
                        v = next_v
                    else:
                        v = 0.0
                imputed.append([t, round(v, 4)])
            out_data[sid][mname] = imputed

    with open(out_file, 'w') as f:
        json.dump(out_data, f, separators=(',', ':'), sort_keys=True)

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > /app/wrapper.c
#include <stdlib.h>
#include <stdio.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <input.csv> <output.json>\n", argv[0]);
        return 1;
    }
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "python3 /app/.hidden_impl.py \"%s\" \"%s\"", argv[1], argv[2]);
    return system(cmd);
}
EOF

    gcc /app/wrapper.c -o /app/config_drift_analyzer
    rm /app/wrapper.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
