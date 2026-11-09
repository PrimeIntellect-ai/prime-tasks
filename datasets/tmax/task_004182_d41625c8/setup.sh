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

vendors = [f"V{str(i).zfill(4)}" for i in range(1, 101)]

def mutate(text, changes):
    chars = list(text)
    for _ in range(changes):
        idx = random.randint(0, len(chars)-1)
        chars[idx] = random.choice('abcdefghijklmnopqrstuvwxyz')
    return "".join(chars)

data = []
for v in vendors:
    base_en = f"Super Widget Model {random.randint(10, 50)}"
    base_fr = f"Super Machin Modèle {random.randint(10, 50)}"
    base_es = f"Super Artefacto Modelo {random.randint(10, 50)}"

    # Introduce some near duplicates manually
    if random.random() < 0.15:
        base_en = mutate(base_en, 1)
    if random.random() < 0.15:
        base_fr = mutate(base_fr, 1)

    data.append({
        "vendor_id": v,
        "name_en": base_en,
        "desc_en": "Standard description EN.",
        "name_fr": base_fr,
        "desc_fr": "Standard description FR.",
        "name_es": base_es,
        "desc_es": "Standard description ES."
    })

with open('/home/user/raw_products.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["vendor_id", "name_en", "desc_en", "name_fr", "desc_fr", "name_es", "desc_es"])
    writer.writeheader()
    writer.writerows(data)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
