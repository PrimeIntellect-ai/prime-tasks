#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
pip3 install pytest Pillow

mkdir -p /app
cd /app

# 1. Generate sequences.fasta
cat << 'EOF' > generate_fasta.py
import random
random.seed(42)
with open('sequences.fasta', 'w') as f:
    for i in range(1, 101):
        length = random.randint(150, 300)
        seq = ''.join(random.choices(['A', 'C', 'G', 'T'], k=length))
        f.write(f">seq_{i}\n{seq}\n")
EOF
python3 generate_fasta.py

# 2. Generate lab_notes.png (Image Fixture)
cat << 'EOF' > generate_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((20, 40), "Target parameter k_deg = 0.284", fill=(0, 0, 0))
img.save('lab_notes.png')
EOF
python3 generate_image.py

# 3. Create the broken simulate.py
cat << 'EOF' > simulate.py
def adaptive_euler(k_syn, k_deg, t_end=100.0):
    t = 0.0
    P = 0.0
    dt = 1.0
    tol = 1e-4

    while t < t_end:
        # Prevent shooting past t_end
        if t + dt > t_end:
            dt = t_end - t

        # Full step
        dP = k_syn - k_deg * P
        P_next = P + dP * dt

        # Two half steps for error estimation
        P_half = P + dP * (dt / 2.0)
        dP_half = k_syn - k_deg * P_half
        P_next_half = P_half + dP_half * (dt / 2.0)

        error = abs(P_next - P_next_half) + 1e-12

        # BUG: Incorrect adaptation logic. 
        # Should be (tol / error)**0.5, but is inverted causing divergence.
        dt_new = dt * (error / tol)**0.5 

        dt = min(max(dt_new, 1e-4), 2.0)

        t += dt
        P = P_next_half # using the more accurate estimate

    return P
EOF

rm generate_fasta.py generate_image.py

chmod -R 777 /app

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
