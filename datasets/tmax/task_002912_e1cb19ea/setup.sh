#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_graph.py
import random

random.seed(42)

nodes = [f"<http://example.org/User{i}>" for i in range(1, 1001)]
target = "<http://example.org/TargetUser>"

follows = "<follows>"
knows = "<knows>"

triples = []

# Create followers of target
followers = random.sample(nodes, 50)
for f in followers:
    triples.append(f"{f} {follows} {target} .")

# Add some noise follows
for _ in range(500):
    u1, u2 = random.sample(nodes, 2)
    triples.append(f"{u1} {follows} {u2} .")

# Create knows relationships
for _ in range(2000):
    u1, u2 = random.sample(nodes, 2)
    triples.append(f"{u1} {knows} {u2} .")

# Plant specific targets to ensure the query returns results
planted_pairs = [
    ("<http://example.org/UserA>", "<http://example.org/UserB>"),
    ("<http://example.org/UserC>", "<http://example.org/UserD>"),
    ("<http://example.org/UserE>", "<http://example.org/UserB>")
]

for u1, u2 in planted_pairs:
    triples.append(f"{u1} {follows} {target} .")
    triples.append(f"{u2} {follows} {target} .")
    triples.append(f"{u1} {knows} {u2} .")

with open("/home/user/graph.nt", "w") as f:
    for t in triples:
        f.write(t + "\n")
EOF

    python3 /home/user/generate_graph.py
    rm /home/user/generate_graph.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
