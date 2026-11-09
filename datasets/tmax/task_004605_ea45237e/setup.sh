#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    python3 << 'EOF'
import os
import json
import random

os.makedirs("/home/user/data", exist_ok=True)
output_path = "/home/user/data/equations.jsonl"

templates = [
    "f(x) = a * x^2 + b * x + c",
    "E = m * c^2",
    "F = m * a",
    "A = \\pi * r^2",
    "c^2 = a^2 + b^2",
    "v = u + a * t",
    "x = ( -b + \\sqrt{ b^2 - 4 * a * c } ) / ( 2 * a )",
    "P = V * I",
    "F = G * (m1 * m2) / r^2"
]

# Create exactly 10,000 records
random.seed(42)
with open(output_path, "w") as f:
    for i in range(10000):
        eq = random.choice(templates)
        # Randomly vary the variables or numbers to create variations that normalize to the same template
        if eq == "F = m * a":
            eq = f"{random.choice(['F','G','H'])} = {random.choice(['x','y','z'])} * {random.choice(['a','b','c'])}"

        # Inject malformed unicode in 5% of lines
        note = "Valid equation"
        if random.random() < 0.05:
            note = "Malformed \\u123" # Truncated escape
        elif random.random() < 0.05:
            note = "Malformed \\uXYZW" # Invalid hex

        record = {
            "id": i,
            "note": note,
            "equation": eq
        }

        # Convert to JSON string
        line = json.dumps(record)

        # Actually break the JSON string if it's supposed to be malformed
        if "Malformed \\u123" in note:
            line = line.replace("\\\\u123", "\\u123")
        elif "Malformed \\uXYZW" in note:
            line = line.replace("\\\\uXYZW", "\\uXYZW")

        f.write(line + "\n")
EOF

    chmod -R 777 /home/user
