#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow numpy

    mkdir -p /app

    cat << 'EOF' > /tmp/create_image.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (300, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "DAMPING=0.85", fill=(0,0,0))
d.text((10,50), "TOLERANCE=1e-7", fill=(0,0,0))
img.save('/app/config.png')
EOF
    python3 /tmp/create_image.py

    cat << 'EOF' > /app/pagerank.py
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import numpy as np

DAMPING = 0.50 # BUG: wrong parameter
TOLERANCE = 1e-2 # BUG: wrong parameter

def compute_pagerank(graph_dict):
    nodes = list(graph_dict.keys())
    N = len(nodes)
    if N == 0: return {}

    # Initialize
    ranks = {n: 1.0/N for n in nodes}

    for iteration in range(1000):
        new_ranks = {}
        diff = 0.0
        for node in nodes:
            # BUG 1: Convergence failure / math error - missing DAMPING * sum
            # Expected: (1.0 - DAMPING) / N + DAMPING * sum(...)
            # Buggy: (1.0 - DAMPING) + sum(...)
            rank_sum = 0.0
            for in_node, out_edges in graph_dict.items():
                if node in out_edges:
                    rank_sum += ranks[in_node] / len(out_edges)

            # BUG 2: Precision loss tracking - truncating to float16
            r = (1.0 - DAMPING) / N + rank_sum # math bug missing damping multiplier
            r = float(np.float16(r)) 
            new_ranks[node] = r
            diff += abs(new_ranks[node] - ranks[node])

        ranks = new_ranks
        if diff < TOLERANCE:
            return ranks, iteration + 1

    return ranks, 1000

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/calculate':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data)

            ranks, iters = compute_pagerank(data.get('graph', {}))

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'ranks': ranks, 'iterations': iters}).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), Handler)
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
