#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gawk bc
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the lab_notes.png image using Python
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (400, 200), color='white')
d = ImageDraw.Draw(img)
text = 'Experiment 42\nGrowth Rate r = 0.45\nCarrying Capacity K = 5000'
d.text((10,10), text, fill='black')
img.save('/app/lab_notes.png')
"

    # Create the oracle solver
    cat << 'EOF' > /app/oracle_solver
#!/bin/bash
awk -v P0="$1" -v dt="$2" -v N="$3" -v r=0.45 -v K=5000 'BEGIN {
  P = P0;
  for (i=0; i<N; i++) {
    dP = r * P * (1 - P / K);
    P = P + dP * dt;
  }
  printf "%.4f\n", P;
}'
EOF
    chmod +x /app/oracle_solver

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
