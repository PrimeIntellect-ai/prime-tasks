#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        tesseract-ocr

    pip3 install pytest Pillow

    mkdir -p /app
    mkdir -p /home/user

    # Generate image and routes.json
    python3 -c "
import json
import random
from PIL import Image, ImageDraw

# Generate image
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), 'RELEASE_VERSION: 14.5.2-beta', fill=(0, 0, 0))
img.save('/app/dashboard.png')

# Generate routes.json
routes = []
for i in range(5000):
    module = f'module_{random.randint(1, 100)}'
    build_id = random.randint(1, 10000)
    routes.append({'url': f'https://example.com/api?module={module}', 'build_id': build_id})
with open('/app/routes.json', 'w') as f:
    json.dump(routes, f)
"

    # Create inefficient merge_builds.py
    cat << 'EOF' > /home/user/merge_builds.py
import json
import sys
from urllib.parse import urlparse, parse_qs

def process_routes(input_file, output_file):
    with open(input_file, 'r') as f:
        routes = json.load(f)

    latest_builds = []

    # Inefficient O(N^2) approach
    for i in range(len(routes)):
        parsed1 = urlparse(routes[i]['url'])
        mod1 = parse_qs(parsed1.query).get('module', [''])[0]

        is_latest = True
        for j in range(len(routes)):
            if i == j:
                continue
            parsed2 = urlparse(routes[j]['url'])
            mod2 = parse_qs(parsed2.query).get('module', [''])[0]

            if mod1 == mod2 and routes[j]['build_id'] > routes[i]['build_id']:
                is_latest = False
                break

        if is_latest:
            found = False
            for b in latest_builds:
                if b['module'] == mod1:
                    found = True
                    break
            if not found:
                latest_builds.append({'module': mod1, 'build_id': routes[i]['build_id']})

    with open(output_file, 'w') as f:
        json.dump(latest_builds, f)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: python merge_builds.py <output_file>')
        sys.exit(1)
    process_routes('/app/routes.json', sys.argv[1])
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
