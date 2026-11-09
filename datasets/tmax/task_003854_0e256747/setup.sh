#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest pandas

    mkdir -p /app
    # Generate the image fixture using ImageMagick
    convert -size 400x120 xc:white -font DejaVu-Sans -pointsize 16 -fill black \
    -draw "text 10,20 'P(C=0)=0.65'" \
    -draw "text 10,40 'P(C=1)=0.35'" \
    -draw "text 10,60 'P(F1|C=0)=0.1, P(F2|C=0)=0.9'" \
    -draw "text 10,80 'P(F1|C=1)=0.8, P(F2|C=1)=0.2'" \
    /app/priors.png

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import csv
import math
import random

random.seed(42)

p_c0 = 0.65
p_c1 = 0.35
p_f1_c0 = 0.1
p_f2_c0 = 0.9
p_f1_c1 = 0.8
p_f2_c1 = 0.2

data = []
golden = []

for uid in range(1, 21):
    count_f1 = random.randint(0, 5)
    count_f2 = random.randint(0, 5)

    for _ in range(count_f1):
        data.append((uid, "2023-10-01T12:00:00Z", "F1"))
    for _ in range(count_f2):
        data.append((uid, "2023-10-01T12:05:00Z", "F2"))

    s0 = math.log(p_c0) + count_f1 * math.log(p_f1_c0) + count_f2 * math.log(p_f2_c0)
    s1 = math.log(p_c1) + count_f1 * math.log(p_f1_c1) + count_f2 * math.log(p_f2_c1)

    # Avoid overflow in exp
    max_s = max(s0, s1)
    exp_s0 = math.exp(s0 - max_s)
    exp_s1 = math.exp(s1 - max_s)
    prob_1 = exp_s1 / (exp_s0 + exp_s1)

    golden.append((uid, prob_1))

random.shuffle(data)

with open("/home/user/raw_data.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["user_id", "timestamp", "feature_type"])
    writer.writerows(data)

with open("/tmp/golden_results.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["user_id", "prob_1"])
    for uid, p1 in golden:
        writer.writerow([uid, f"{p1:.6f}"])
EOF
    python3 /tmp/setup_data.py

    chmod -R 777 /home/user
