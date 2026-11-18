#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr tesseract-ocr-eng jq
    pip3 install pytest Pillow

    mkdir -p /app/clean /app/evil

    # Generate specs.png using Pillow
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), 'Target Metric: f1_score', fill=(0, 0, 0))
img.save('/app/specs.png')
"

    # Create clean corpus
    cat << 'EOF' > /app/clean/clean1.json
{"experiment_id": 1, "metric": "f1_score", "model_path": "models/exp1/model.bin"}
EOF
    cat << 'EOF' > /app/clean/clean2.json
{"experiment_id": 5, "metric": "f1_score", "model_path": "models/exp5/model_v2.bin"}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/evil/evil1.json
{"experiment_id": 2, "metric": "f1_score", "model_path": "models/exp2/../../etc/passwd"}
EOF
    cat << 'EOF' > /app/evil/evil2.json
{"experiment_id": 3, "metric": "f1_score", "model_path": "models/exp3/model.bin; rm -rf /"}
EOF
    cat << 'EOF' > /app/evil/evil3.json
{"experiment_id": 4, "metric": "accuracy", "model_path": "models/exp4/model.bin"}
EOF
    cat << 'EOF' > /app/evil/evil4.json
{"experiment_id": 6, "metric": "f1_score", "model_path": "models/exp6/`whoami`"}
EOF
    cat << 'EOF' > /app/evil/evil5.json
{"experiment_id": 7, "metric": "f1_score", "model_path": "models/exp7/model.bin | bash"}
EOF
    cat << 'EOF' > /app/evil/evil6.json
{"experiment_id": 8, "metric": "f1_score", "model_path": "models/exp8/model.bin & echo pwned"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
