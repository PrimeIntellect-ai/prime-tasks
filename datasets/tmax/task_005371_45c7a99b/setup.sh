#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        libsm6 \
        libxext6 \
        libgl1-mesa-glx

    pip3 install pytest pandas opencv-python Pillow numpy

    mkdir -p /app
    mkdir -p /home/user

    # Generate CSV
    cat << 'EOF' > /home/user/org_chart.csv
dept_id,parent_id,employees
D_1,,10
D_2,D_1,20
D_3,D_1,15
D_4,D_2,5
D_5,D_2,30
D_6,D_3,12
D_7,D_3,8
D_8,D_4,50
D_9,D_6,2
D_10,D_8,100
EOF

    # Generate Oracle
    cat << 'EOF' > /app/oracle_query_tool.py
import sys
import json
import csv

video_seq = ['R', 'G', 'B', 'R', 'R', 'G', 'B', 'B', 'G', 'R', 'R', 'B', 'G', 'G', 'R', 'B', 'B', 'R', 'G', 'G', 'R', 'R', 'R', 'B', 'B', 'B', 'G', 'G', 'G', 'R', 'B', 'G', 'R', 'B', 'G', 'R', 'B', 'G', 'R', 'B', 'G', 'G', 'R', 'R', 'B', 'B', 'R', 'G', 'B', 'R', 'G', 'B', 'R', 'G', 'B', 'R', 'G', 'B', 'R', 'G']

def get_emp(csv_path, target_id):
    tree = {}
    emps = {}
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            d = row['dept_id']
            p = row['parent_id']
            e = int(row['employees'])
            emps[d] = e
            if p not in tree:
                tree[p] = []
            tree[p].append(d)

    def dfs(node):
        total = emps.get(node, 0)
        for child in tree.get(node, []):
            total += dfs(child)
        return total

    return dfs(target_id)

start_sec = int(sys.argv[1])
end_sec = int(sys.argv[2])
dept_id = sys.argv[3]

sub = video_seq[start_sec:end_sec+1]
r_c = sub.count('R')
g_c = sub.count('G')
b_c = sub.count('B')

total_emp = get_emp('/home/user/org_chart.csv', dept_id)

print(json.dumps({
    "R_score": r_c * total_emp,
    "G_score": g_c * total_emp,
    "B_score": b_c * total_emp
}))
EOF

    # Generate Video
    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

video_seq = ['R', 'G', 'B', 'R', 'R', 'G', 'B', 'B', 'G', 'R', 'R', 'B', 'G', 'G', 'R', 'B', 'B', 'R', 'G', 'G', 'R', 'R', 'R', 'B', 'B', 'B', 'G', 'G', 'G', 'R', 'B', 'G', 'R', 'B', 'G', 'R', 'B', 'G', 'R', 'B', 'G', 'G', 'R', 'R', 'B', 'B', 'R', 'G', 'B', 'R', 'G', 'B', 'R', 'G', 'B', 'R', 'G', 'B', 'R', 'G']

colors = {
    'R': (0, 0, 255),
    'G': (0, 255, 0),
    'B': (255, 0, 0)
}

out = cv2.VideoWriter('/app/dashboard.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (100, 100))
for c in video_seq:
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    frame[:] = colors[c]
    out.write(frame)
out.release()
EOF

    python3 /app/generate_video.py
    rm /app/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
