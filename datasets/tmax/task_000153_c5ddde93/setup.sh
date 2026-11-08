#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow --no-cache-dir

    mkdir -p /app

    cat << 'EOF' > /app/requests.json
[
  {"path": "/admin/dashboard", "query_params": {"token": "A1B2C3D4"}},
  {"path": "/admin/settings", "query_params": {"token": "invalid_token"}},
  {"path": "/api/users", "query_params": {"q": "name=John"}},
  {"path": "/api/search", "query_params": {"q": "1 UNION SELECT * FROM users"}},
  {"path": "/login", "query_params": {}},
  {"path": "/unknown", "query_params": {}},
  {"path": "/admin/super", "query_params": {"token": "12345678"}},
  {"path": "/api/comments", "query_params": {"q": "<script>alert(1)</script>"}}
]
EOF

    cat << 'EOF' > /app/ground_truth.json
["ALLOW", "BLOCK", "ALLOW", "BLOCK", "ALLOW", "BLOCK", "ALLOW", "BLOCK"]
EOF

    cat << 'EOF' > /tmp/make_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 400), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = """State Machine WAF Rules:
Rule 1: Path starts with '/admin' -> Check param 'token'. If 'token' matches regex '^[A-Z0-9]{8}$', ALLOW. Otherwise BLOCK.
Rule 2: Path starts with '/api' -> Check param 'q'. If 'q' contains '<script>' or 'UNION SELECT', BLOCK. Otherwise ALLOW.
Rule 3: Path equals '/login' -> ALLOW.
Rule 4: All other paths -> BLOCK.
"""
d.text((10,10), text, fill=(0,0,0))
img.save('/app/waf_rules.png')
EOF

    python3 /tmp/make_img.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
