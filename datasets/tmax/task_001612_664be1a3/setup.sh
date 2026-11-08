#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest networkx flask fastapi uvicorn pytesseract Pillow requests httpx

    mkdir -p /app

    cat << 'EOF' > /app/nodes.csv
node_id,node_type,metric_a,metric_b
N1,ROUTER,10.0,5.0
N2,SWITCH,4.0,12.0
N3,SERVER,1.0,8.0
N4,SWITCH,7.0,2.0
EOF

    cat << 'EOF' > /app/edges.csv
source_id,target_id
N1,N2
N1,N3
N2,N4
N3,N4
N4,N1
EOF

    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color='white')
d = ImageDraw.Draw(img)
text = 'ROUTER: metric_a + metric_b\nSWITCH: metric_a * 2\nSERVER: metric_b * 3'
d.text((10,10), text, fill='black')
img.save('/app/cost_formula.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
