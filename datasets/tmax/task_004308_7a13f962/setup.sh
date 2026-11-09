#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang-go imagemagick gsfonts
pip3 install pytest

mkdir -p /app

# Create the image using ImageMagick
convert -background white -fill black -font Courier -pointsize 24 label:"mu=120\nsigma=30\nthreshold=180" /app/system_model.png

# Create the profiling_data.csv
cat << 'EOF' > /tmp/gen_csv.py
import random
random.seed(42)
N = 100
target_mean = 126.5
# generate random values around target
vals = [random.gauss(126.5, 30) for _ in range(N)]
# force exact mean
current_mean = sum(vals) / N
diff = target_mean - current_mean
vals = [v + diff for v in vals]
with open('/app/profiling_data.csv', 'w') as f:
    for v in vals:
        f.write(f"{v}\n")
EOF
python3 /tmp/gen_csv.py
rm /tmp/gen_csv.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
