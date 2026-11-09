#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_logs.py
import random
import csv

random.seed(42)

locales = ["en_US", "fr_FR", "de_DE", "es_ES", "ja_JP"]
valid_keys = ["menu_file_01", "menu_edit_02", "menu_view_99", "menu_help_00"]
invalid_keys = ["menu_12", "button_ok", "menu_file_abc", "dialog_error"]

with open("/home/user/loc_logs.csv", "w", newline="") as f:
    writer = csv.writer(f)
    base_time = 1700000000
    for i in range(50000):
        ts = base_time + random.randint(0, 100000)
        loc = random.choice(locales)

        if random.random() < 0.3:
            key = random.choice(valid_keys)
        else:
            key = random.choice(invalid_keys)

        render_time = random.randint(10, 200)

        if random.random() < 0.001:
            f.write("malformed,line,here\n")
            continue

        writer.writerow([ts, loc, key, render_time])
EOF
    python3 /tmp/setup_logs.py

    chmod -R 777 /home/user
