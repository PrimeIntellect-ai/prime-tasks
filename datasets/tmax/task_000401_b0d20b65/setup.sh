#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Pillow requests fastapi uvicorn

    mkdir -p /app
    mkdir -p /home/user/legacy_project
    mkdir -p /app/eval_project

    # Generate spec.png
    python3 -c '
from PIL import Image, ImageDraw
text = """Project Organizer API Spec
Endpoint: POST /organize
Payload: {"dir": "/path/to/project"}
Response JSON format: 
{
  "score": <float>,
  "modules": {
    "module_1": ["fileA.py", "fileB.py"],
    "module_2": ["fileC.py"]
  }
}

Constraint: Max 3 files per module.
Dependencies are directed edges. FileA imports FileB means A -> B.
Modularity Score Formula:
Score = (Number of intra-module edges) / (Total number of edges in the project)
If Total edges == 0, Score = 1.0."""

img = Image.new("RGB", (800, 600), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), text, fill=(0,0,0))
img.save("/app/spec.png")
'

    # Generate legacy project files
    python3 -c '
import os
for i in range(10):
    with open(f"/home/user/legacy_project/file{i}.py", "w") as f:
        f.write(f"# Legacy file {i}\n")
'

    # Generate eval project files with specific dependency graph
    python3 -c '
import os
edges = {
    0: [1], 1: [2],
    3: [4], 4: [5],
    6: [7], 7: [8],
    9: [10], 10: [11],
    12: [13], 13: [14],
    15: [16], 16: [17],
    18: [19],
    2: [3], 5: [6]
}

for i in range(20):
    with open(f"/app/eval_project/file{i:02d}.py", "w") as f:
        if i in edges:
            for target in edges[i]:
                f.write(f"import file{target:02d}\n")
        else:
            f.write("# No imports\n")
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
