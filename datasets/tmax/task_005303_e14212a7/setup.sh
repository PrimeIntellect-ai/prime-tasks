#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the compliance rule image using Python and Pillow
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """Compliance Rule 8A: 
Partition Key: account_id
Sort Key: tx_time
Aggregation: 3-period rolling sum (current row + up to 2 preceding rows)
Target Field: amount"""
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/compliance_rule.png')
EOF
    python3 /tmp/make_image.py

    # Create the oracle executable
    cat << 'EOF' > /app/oracle_audit_checker
#!/usr/bin/env python3
import sys
import json
from collections import defaultdict

def main():
    print(json.dumps({"account_id": 1, "tx_time": 1}))

    records = []
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        records.append(json.loads(line))

    groups = defaultdict(list)
    for r in records:
        groups[r['account_id']].append(r)

    output_records = []
    for acc in sorted(groups.keys()):
        group = groups[acc]
        group.sort(key=lambda x: x['tx_time'])
        for i in range(len(group)):
            start_idx = max(0, i - 2)
            window = group[start_idx:i+1]
            rolling_sum = sum(item['amount'] for item in window)

            new_r = dict(group[i])
            # Rounding to avoid minor float precision differences between Python and Rust
            new_r['compliance_metric'] = round(rolling_sum, 4)
            output_records.append(new_r)

    for r in output_records:
        print(json.dumps(r))

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_audit_checker

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
