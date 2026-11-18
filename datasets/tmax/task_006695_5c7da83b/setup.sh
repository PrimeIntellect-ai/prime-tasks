#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
import random
import os
import collections
import re

random.seed(42)

def generate_data():
    output_path = '/home/user/locales_etl_dump.csv'
    with open(output_path, 'w', newline='') as f:
        writer = csv.writer(f)

        base_ids = [f"STR_{i:04d}" for i in range(1000)]

        records = []
        current_time = 1600000000

        for i in range(5000):
            current_time += random.randint(10, 100)
            str_id = random.choice(base_ids)
            locale = random.choice(["fr-FR", "es-ES", "de-DE", "ja-JP"])

            source = f"Source text for {str_id}"

            if random.random() < 0.1:
                translation = f"Translation avec MACRO text"
            else:
                translation = f"Texte traduit normal"

            if random.random() < 0.2:
                score = ""
            else:
                score = round(random.uniform(40.0, 99.9), 1)

            records.append((current_time, str_id, locale, source, translation, score))

            if random.random() < 0.3:
                dup_time = current_time + random.randint(300, 1000)
                dup_score = "" if random.random() < 0.5 else round(random.uniform(40.0, 99.9), 1)
                records.append((dup_time, str_id, locale, source, translation, dup_score))

        random.shuffle(records)

        for r in records:
            writer.writerow(r)

def generate_golden():
    records = {}
    with open('/home/user/locales_etl_dump.csv', 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            ts, sid, loc, src, tr, sc = row
            ts = int(ts)

            if loc != 'fr-FR': continue

            if re.search(r'[A-Z]{3,}', tr):
                continue

            if sid not in records or records[sid]['ts'] < ts:
                records[sid] = {'ts': ts, 'sc': sc}

    sorted_recs = sorted(records.items(), key=lambda x: x[1]['ts'])

    last_score = 50.0
    window = collections.deque(maxlen=3)

    with open('/home/user/fr_FR_rolling_stats.csv.golden', 'w', newline='') as f:
        writer = csv.writer(f)
        for sid, data in sorted_recs:
            sc_str = data['sc']
            if sc_str == "":
                sc_val = last_score
            else:
                sc_val = float(sc_str)

            last_score = sc_val
            window.append(sc_val)

            rolling_avg = sum(window) / len(window)
            writer.writerow([data['ts'], sid, round(sc_val, 1), f"{rolling_avg:.2f}"])

if __name__ == '__main__':
    generate_data()
    generate_golden()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
