#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang git wget
    pip3 install pytest

    # Clone blackfriday
    mkdir -p /app
    git clone --depth 1 --branch v2.1.0 https://github.com/russross/blackfriday.git /app/blackfriday

    # Perturb block.go (approximate for the heading bug)
    sed -i 's/text := data\[p:\]/text := data\[p+1:\]/g' /app/blackfriday/block.go

    # Generate markdown files and ground truth
    python3 -c '
import os
import json

os.makedirs("/home/user/docs", exist_ok=True)
ground_truth = []

for i in range(50):
    is_large = (i % 2 == 0)
    filename = f"doc_{i}.md"
    filepath = os.path.join("/home/user/docs", filename)

    with open(filepath, "w") as f:
        if is_large:
            heading = f"RandomWord{i}"
            f.write(f"# {heading}\n\n")
            f.write("A" * 1500)
            ground_truth.append({"filename": filename, "heading": heading})
        else:
            f.write("# SmallDoc\n\n")
            f.write("B" * 500)

with open("/opt/ground_truth.json", "w") as f:
    json.dump(ground_truth, f)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
