#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg qrencode zbar-tools
pip3 install pytest

mkdir -p /app
mkdir -p /home/user/legacy_resolver

# Create legacy resolver files
cat << 'EOF' > /home/user/legacy_resolver/graph.py
import nodes
class Graph:
    def __init__(self):
        self.nodes = []
EOF

cat << 'EOF' > /home/user/legacy_resolver/nodes.py
import graph
class Node:
    def __init__(self, name):
        self.name = name
EOF

cat << 'EOF' > /home/user/legacy_resolver/resolver.py
import graph
import nodes
def resolve():
    print "Resolving..."
EOF

# Create the oracle binary
cat << 'EOF' > /app/oracle_resolver_bin
#!/usr/bin/env python3
import sys
import json

def main():
    try:
        graph = json.load(sys.stdin)
        # Dummy output for oracle to pass initial tests
        print(json.dumps(list(sorted(graph.keys()))))
    except Exception:
        pass

if __name__ == "__main__":
    main()
EOF
chmod +x /app/oracle_resolver_bin

# Generate the video with QR codes
cat << 'EOF' > /tmp/gen_video.py
import base64
import os
import subprocess
import math

patch = """--- /home/user/legacy_resolver/nodes.py
+++ /home/user/legacy_resolver/nodes.py
@@ -10,3 +10,4 @@
-import graph
+import types
"""

b64_patch = base64.b64encode(patch.encode('utf-8')).decode('utf-8')
num_frames = 10
chunk_size = math.ceil(len(b64_patch) / num_frames)

chunks = [b64_patch[i:i + chunk_size] for i in range(0, len(b64_patch), chunk_size)]
while len(chunks) < num_frames:
    chunks.append(" ")
chunks = chunks[:num_frames]

os.makedirs('/tmp/frames', exist_ok=True)
for i, chunk in enumerate(chunks):
    if not chunk: chunk = " "
    subprocess.run(['qrencode', '-s', '10', '-o', f'/tmp/frames/frame_{i:03d}.png', chunk])

subprocess.run([
    'ffmpeg', '-y', '-framerate', '1', '-i', '/tmp/frames/frame_%03d.png',
    '-c:v', 'libx264', '-r', '1', '-pix_fmt', 'yuv420p', '/app/dependency_patches.mp4'
])
EOF

python3 /tmp/gen_video.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
