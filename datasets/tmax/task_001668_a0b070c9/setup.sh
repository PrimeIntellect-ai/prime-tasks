#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr cargo rustc
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create the config image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (500, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((20, 50), 'PROXY_PORT=8080', fill=(0, 0, 0))
d.text((20, 100), 'ALLOWED_DIR=/var/lib/plugins/', fill=(0, 0, 0))
img.save('/app/config_spec.png')
"

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/1.json
{"pipeline": [{"step_id": "A", "plugin_path": "/var/lib/plugins/libA.so", "depends_on": []}]}
EOF

    cat << 'EOF' > /app/corpus/clean/2.json
{"pipeline": [{"step_id": "A", "plugin_path": "/var/lib/plugins/libA.so", "depends_on": []}, {"step_id": "B", "plugin_path": "/var/lib/plugins/libB.so", "depends_on": ["A"]}]}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/cycle.json
{"pipeline": [{"step_id": "A", "plugin_path": "/var/lib/plugins/libA.so", "depends_on": ["B"]}, {"step_id": "B", "plugin_path": "/var/lib/plugins/libB.so", "depends_on": ["A"]}]}
EOF

    cat << 'EOF' > /app/corpus/evil/path.json
{"pipeline": [{"step_id": "A", "plugin_path": "/etc/shadow", "depends_on": []}]}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
