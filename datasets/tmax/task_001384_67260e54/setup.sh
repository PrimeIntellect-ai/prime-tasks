#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate the video
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=10 -c:v libx264 -pix_fmt yuv420p /app/pipeline_test.mp4 -y

    # Create oracle_router.py
    cat << 'EOF' > /app/oracle_router.py
import sys
import urllib.parse
import json
import os
import subprocess
from collections import defaultdict, deque

def extract_frame_brightness(video_path, timestamp):
    cmd = [
        "ffmpeg", "-ss", str(timestamp), "-i", video_path, 
        "-vframes", "1", "-f", "rawvideo", "-pix_fmt", "gray", "-"
    ]
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
        if not res.stdout: return 0
        return sum(res.stdout) // len(res.stdout)
    except:
        return 0

def process(url_str):
    try:
        parsed = urllib.parse.urlparse(url_str)
        if parsed.scheme != "https" or parsed.netloc != "ci.local" or parsed.path != "/build/trigger":
            return {"status": "error"}
        qs = urllib.parse.parse_qs(parsed.query)

        video_path = qs.get("video", [""])[0]
        abspath = os.path.abspath(video_path)
        if not abspath.startswith("/app/") or not os.path.exists(abspath):
            return {"status": "error"}

        nodes_raw = qs.get("nodes", [""])[0]
        edges_raw = qs.get("edges", [""])[0]

        nodes = {}
        if nodes_raw:
            for n in nodes_raw.split(","):
                name, ts = n.split(":")
                nodes[name] = float(ts)

        adj = defaultdict(list)
        indegree = {n: 0 for n in nodes}

        if edges_raw:
            for e in edges_raw.split(","):
                u, v = e.split("->")
                if u not in nodes or v not in nodes:
                    return {"status": "error"}
                adj[u].append(v)
                indegree[v] += 1

        order = []
        zero_in = [n for n in nodes if indegree[n] == 0]

        while zero_in:
            zero_in.sort()
            u = zero_in.pop(0)
            order.append(u)
            for v in adj[u]:
                indegree[v] -= 1
                if indegree[v] == 0:
                    zero_in.append(v)

        if len(order) != len(nodes):
            return {"status": "error"}

        results = {}
        for node in order:
            results[node] = extract_frame_brightness(abspath, nodes[node])

        return {"status": "success", "order": order, "results": results}
    except Exception as e:
        return {"status": "error"}

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(json.dumps({"status": "error"}))
        sys.exit(0)
    print(json.dumps(process(sys.argv[1])))
EOF
    chmod +x /app/oracle_router.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
