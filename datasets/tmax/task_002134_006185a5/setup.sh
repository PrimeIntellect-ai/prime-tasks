#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    python3 -c "
import cv2
import numpy as np
import json
import os

# Generate video
out = cv2.VideoWriter('/app/reference.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100))
for i in range(50):
    if i in [5, 12, 18, 24, 30, 36, 42]:
        frame = np.ones((100, 100, 3), dtype=np.uint8) * 255
    else:
        frame = np.zeros((100, 100, 3), dtype=np.uint8)
    out.write(frame)
out.release()

# Generate clean workflows
clean1 = [{'source': 'N1', 'target': 'N2'}, {'source': 'N2', 'target': 'N3'},
          {'source': 'N3', 'target': 'N4'}, {'source': 'N4', 'target': 'N5'},
          {'source': 'N5', 'target': 'N6'}, {'source': 'N6', 'target': 'N7'}]
with open('/app/corpus/clean/clean1.json', 'w') as f:
    json.dump(clean1, f)

clean2 = [{'source': 'A', 'target': 'B'}, {'source': 'A', 'target': 'C'}]
with open('/app/corpus/clean/clean2.json', 'w') as f:
    json.dump(clean2, f)

# Generate evil workflows
evil1 = [{'source': 'N1', 'target': 'N2'}, {'source': 'N2', 'target': 'N3'},
         {'source': 'N3', 'target': 'N4'}, {'source': 'N4', 'target': 'N5'},
         {'source': 'N5', 'target': 'N6'}, {'source': 'N6', 'target': 'N7'},
         {'source': 'N7', 'target': 'N8'}]
with open('/app/corpus/evil/evil1.json', 'w') as f:
    json.dump(evil1, f)

evil2 = [{'source': 'A', 'target': 'B'}, {'source': 'B', 'target': 'C'}, {'source': 'C', 'target': 'A'}]
with open('/app/corpus/evil/evil2.json', 'w') as f:
    json.dump(evil2, f)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
