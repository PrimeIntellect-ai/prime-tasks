#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
pip3 install pytest

mkdir -p /app

# Generate the pipeline specs image
convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 14 -fill black -annotate +10+20 "ETL CONFIGURATION v2.1\n----------------------\nDEDUPLICATION_KEY: \"tx_id\"\nORDER_BY_FIELD: \"timestamp\"\nANOMALY_DETECTION:\n  ALGORITHM: \"STEP_CHANGE\"\n  MAX_STEP_DELTA: 45.5" /app/pipeline_specs.png

# Create the oracle executable
cat << 'EOF' > /app/oracle_cleaner
#!/usr/bin/env python3
import sys
import json

def main():
    if len(sys.argv) != 2:
        sys.exit(1)

    with open(sys.argv[1], 'r') as f:
        lines = f.readlines()

    records = []
    for line in lines:
        line = line.strip()
        if line:
            records.append(json.loads(line))

    # Deduplicate by tx_id, keeping the last occurrence
    seen = {}
    for r in records:
        if 'tx_id' in r:
            seen[r['tx_id']] = r

    deduped = list(seen.values())

    # Sort by timestamp ascending
    deduped.sort(key=lambda x: x.get('timestamp', 0))

    # Anomaly detection (STEP_CHANGE <= 45.5)
    if not deduped:
        return

    accepted = [deduped[0]]
    for r in deduped[1:]:
        if abs(r.get('value', 0.0) - accepted[-1].get('value', 0.0)) <= 45.5:
            accepted.append(r)

    # Print output
    for r in accepted:
        print(json.dumps(r))

if __name__ == '__main__':
    main()
EOF

chmod +x /app/oracle_cleaner

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
