#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import csv, json

authors = [
    (1, "Alice Smith"),
    (2, "Bob Jones"),
    (3, "Charlie Brown"),
    (4, "David Clark"),
    (5, "Eve Davis")
]

with open("/home/user/authors.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["author_id", "name"])
    writer.writerows(authors)

papers = [
    {"id": "p1", "year": 2018, "authors": [1]},
    {"id": "p2", "year": 2019, "authors": [2, 3]},
    {"id": "p3", "year": 2022, "authors": [1, 4]},
    {"id": "p4", "year": 2023, "authors": [5]},
    {"id": "p5", "year": 2021, "authors": [2]},
    {"id": "p6", "year": 2017, "authors": [4]},
    {"id": "p7", "year": 2024, "authors": [1, 2, 3]}
]

with open("/home/user/papers.jsonl", "w") as f:
    for p in papers:
        f.write(json.dumps(p) + "\n")

citations = [
    ("p3", "p1"), # valid: 2022 -> 2018 (Alice +1)
    ("p4", "p1"), # valid: 2023 -> 2018 (Alice +1)
    ("p5", "p1"), # invalid: 2021 -> 2018
    ("p7", "p2"), # valid: 2024 -> 2019 (Bob +1, Charlie +1)
    ("p3", "p2"), # valid: 2022 -> 2019 (Bob +1, Charlie +1)
    ("p4", "p6"), # valid: 2023 -> 2017 (David +1)
    ("p3", "p6"), # valid: 2022 -> 2017 (David +1)
    ("p7", "p6"), # valid: 2024 -> 2017 (David +1)
    ("p7", "p5")  # invalid: 2024 -> 2021 (not before 2020)
]

with open("/home/user/citations.txt", "w") as f:
    for c in citations:
        f.write(f"{c[0]} {c[1]}\n")
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
