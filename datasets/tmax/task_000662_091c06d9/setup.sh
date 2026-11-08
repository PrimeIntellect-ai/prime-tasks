#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr rustc cargo
    pip3 install pytest Pillow

    mkdir -p /app/clean /app/evil

    # Create image using Python and Pillow
    cat << 'EOF' > /tmp/make_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "THRESHOLD=250.5", fill=(0, 0, 0))
img.save('/app/config_formula.png')
EOF
    python3 /tmp/make_img.py

    # Create clean CSVs (mean <= 250.5)
    cat << 'EOF' > /app/clean/1.csv
run_id,inference_time_ms,batch_size
1,10.0,16.0
2,12.0,16.0
EOF

    cat << 'EOF' > /app/clean/2.csv
run_id,inference_time_ms,batch_size
1,15.0,16.0
2,15.0,15.0
EOF

    cat << 'EOF' > /app/clean/3.csv
run_id,inference_time_ms,batch_size
1,10.0,20.0
2,10.0,20.0
EOF

    cat << 'EOF' > /app/clean/4.csv
run_id,inference_time_ms,batch_size
1,10.0,10.0
2,10.0,10.0
EOF

    cat << 'EOF' > /app/clean/5.csv
run_id,inference_time_ms,batch_size
1,5.0,16.0
2,5.0,16.0
EOF

    # Create evil CSVs (mean > 250.5)
    cat << 'EOF' > /app/evil/1.csv
run_id,inference_time_ms,batch_size
1,20.0,16.0
2,22.0,16.0
EOF

    cat << 'EOF' > /app/evil/2.csv
run_id,inference_time_ms,batch_size
1,25.0,16.0
2,25.0,16.0
EOF

    cat << 'EOF' > /app/evil/3.csv
run_id,inference_time_ms,batch_size
1,20.0,20.0
2,20.0,20.0
EOF

    cat << 'EOF' > /app/evil/4.csv
run_id,inference_time_ms,batch_size
1,30.0,10.0
2,30.0,10.0
EOF

    cat << 'EOF' > /app/evil/5.csv
run_id,inference_time_ms,batch_size
1,50.0,10.0
2,50.0,10.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
