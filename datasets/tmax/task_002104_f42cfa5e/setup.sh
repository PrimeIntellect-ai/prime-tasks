#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/configs/clean /app/configs/evil

    # Create policy image
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -annotate +20+40 "Imputation Default: 512" \
        -annotate +20+80 "Max CPU Threshold: 16" \
        -annotate +20+120 "Max Aggregated Delta: 2000" \
        /app/policy_rules.png

    # Create clean configs
    cat << 'EOF' > /app/configs/clean/clean1.json
[
  {"cpu": 4, "memory": 1024},
  {"cpu": 4, "memory": 1200},
  {"cpu": 8}
]
EOF

    cat << 'EOF' > /app/configs/clean/clean2.json
[
  {"cpu": 2, "memory": 512},
  {"cpu": 2, "memory": 512}
]
EOF

    # Create evil configs
    cat << 'EOF' > /app/configs/evil/evil1.json
[
  {"cpu": 32, "memory": 1024}
]
EOF

    cat << 'EOF' > /app/configs/evil/evil2.json
[
  {"cpu": 4, "memory": 1024},
  {"cpu": 4, "memory": 4000}
]
EOF

    cat << 'EOF' > /app/configs/evil/evil3.json
[
  {"cpu": 4},
  {"memory": 1024},
  {}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
