#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-liberation
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate policy.png
    python3 -c '
from PIL import Image, ImageDraw, ImageFont
img = Image.new("RGB", (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 36)
d.text((10, 10), "PROD-X77-SECURE", fill=(0, 0, 0), font=font)
img.save("/app/policy.png")
'

    # Generate config_templates.tar.gz
    mkdir -p /tmp/nest
    echo "environment_id,version,modules,timeout" > /tmp/nest/allowed_keys.csv
    cd /tmp
    tar -cvf inner.tar nest/allowed_keys.csv
    tar -czvf /app/config_templates.tar.gz inner.tar
    cd /

    # Generate clean corpus
    for i in $(seq 1 10); do
        cat <<EOF > /app/corpus/clean/clean_$i.json
{
  "environment_id": "PROD-X77-SECURE",
  "version": "1.0",
  "modules": ["auth", "db"],
  "timeout": 30
}
EOF
    done

    # Generate evil corpus
    # 1. missing environment_id
    echo '{"version": "1.0", "modules": ["auth"]}' > /app/corpus/evil/evil_1.json
    # 2. wrong environment_id
    echo '{"environment_id": "DEV-X77", "version": "1.0"}' > /app/corpus/evil/evil_2.json
    # 3. extra keys
    echo '{"environment_id": "PROD-X77-SECURE", "version": "1.0", "hacked": true}' > /app/corpus/evil/evil_3.json
    # 4. symlink
    echo '{"environment_id": "PROD-X77-SECURE", "version": "1.0"}' > /app/corpus/evil/real_4.json
    ln -s /app/corpus/evil/real_4.json /app/corpus/evil/evil_4.json
    # 5-10. various
    for i in $(seq 5 10); do
        echo '{"environment_id": "PROD-X77-SECURE", "invalid_key": "x"}' > /app/corpus/evil/evil_$i.json
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
