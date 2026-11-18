#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/raw_data/folder1
    mkdir -p /app/raw_data/folder2/subfolder

    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'EXP_ID: ALPHA-992'" /app/experiment_label.png

    cat << 'EOF' > /app/raw_data/folder1/meta_a.json
{
  "dataset_name": "run_A",
  "experiment_id": "ALPHA-992",
  "values": [1, 2, 3]
}
EOF

    cat << 'EOF' > /app/raw_data/folder2/subfolder/records.csv
id,experiment_id,measurement
1,BETA-111,0.5
2,ALPHA-992,0.8
3,GAMMA-000,0.1
EOF

    cat << 'EOF' > /app/raw_data/folder2/config.xml
<?xml version="1.0"?>
<config>
  <experiment_id>ALPHA-992</experiment_id>
  <settings>fast</settings>
</config>
EOF

    cat << 'EOF' > /app/raw_data/folder1/meta_b.json
{
  "dataset_name": "run_B",
  "experiment_id": "BETA-111",
  "values": [4, 5, 6]
}
EOF

    cat << 'EOF' > /app/raw_data/folder2/ignore.xml
<?xml version="1.0"?>
<config>
  <experiment_id>GAMMA-000</experiment_id>
  <settings>slow</settings>
</config>
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
