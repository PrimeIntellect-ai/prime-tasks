#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
import random

random.seed(42)

dates = ["2024-01-01", "2024-01-02", "2024-01-03", "2024-01-04", "2024-01-05"]

def gen_str(length):
    chars = "abcdeこんにちは" # mixed ascii and utf-8
    return "".join(random.choice(chars) for _ in range(length))

with open("/home/user/config_updates.tsv", "w", encoding="utf-8") as f:
    writer = csv.writer(f, delimiter="\t")
    # Add some noise
    for _ in range(5000):
        d = random.choice(dates)
        writer.writerow([d, f"srv-{random.randint(1,100)}", "Timeout", "300"])

    # Add MOTD
    for i in range(100):
        writer.writerow(["2024-01-01", f"srv-{i}", "MOTD", gen_str(5)])
        writer.writerow(["2024-01-02", f"srv-{i}", "MOTD", gen_str(6)])
        writer.writerow(["2024-01-03", f"srv-{i}", "MOTD", gen_str(6)])
        writer.writerow(["2024-01-04", f"srv-{i}", "MOTD", gen_str(35)])
        writer.writerow(["2024-01-05", f"srv-{i}", "MOTD", gen_str(30)])
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
