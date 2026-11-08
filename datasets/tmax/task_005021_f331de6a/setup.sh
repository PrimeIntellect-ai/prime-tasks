#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the /app directory
    mkdir -p /app

    # Create the legacy_cleaner oracle script
    cat << 'EOF' > /app/legacy_cleaner
#!/usr/bin/env python3
import sys
import csv
import hashlib

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    in_file = sys.argv[1]
    out_file = sys.argv[2]

    rows = []
    with open(in_file, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            header = []
        for row in reader:
            if len(row) >= 3:
                rows.append(row)

    seen_hashes = set()
    deduped = []
    for row in rows:
        msg = row[2]
        h = hashlib.sha256(msg.encode('utf-8')).hexdigest()
        if h not in seen_hashes:
            seen_hashes.add(h)
            deduped.append(row)

    for i in range(len(deduped)):
        if not deduped[i][0].strip():
            prev_idx = -1
            prev_val = None
            for j in range(i-1, -1, -1):
                if deduped[j][0].strip():
                    prev_idx = j
                    prev_val = int(deduped[j][0])
                    break
            next_idx = -1
            next_val = None
            for j in range(i+1, len(deduped)):
                if deduped[j][0].strip():
                    next_idx = j
                    next_val = int(deduped[j][0])
                    break

            if prev_val is not None and next_val is not None:
                imputed = prev_val + (next_val - prev_val) * (i - prev_idx) / (next_idx - prev_idx)
                deduped[i][0] = str(int(imputed))

    final_rows = []
    for row in deduped:
        ts = row[0].strip()
        if not ts:
            continue
        try:
            ts_int = int(ts)
        except ValueError:
            continue
        bucket = (ts_int // 60000) * 60000
        final_rows.append([str(bucket), row[1], row[2]])

    final_rows.sort(key=lambda x: (int(x[0]), x[1]))

    with open(out_file, 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['bucket_start_ms', 'user_id', 'message'])
        writer.writerows(final_rows)

if __name__ == '__main__':
    main()
EOF

    chmod +x /app/legacy_cleaner

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
