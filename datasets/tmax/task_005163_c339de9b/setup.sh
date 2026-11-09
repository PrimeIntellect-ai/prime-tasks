#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import random

random.seed(42)
authors = [f'A{i:04d}' for i in range(1, 501)]
papers = [f'P{i:05d}' for i in range(1, 2001)]

edges = set()
for p in papers:
    num_authors = random.randint(1, 5)
    paper_authors = random.sample(authors, k=num_authors)
    for a in paper_authors:
        edges.add((a, p))

with open('/home/user/wrote.csv', 'w') as f:
    for a, p in sorted(edges):
        f.write(f'{a},{p}\n')
"

    chmod -R 777 /home/user
