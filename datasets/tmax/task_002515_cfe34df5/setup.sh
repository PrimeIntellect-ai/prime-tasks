#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr g++ make
    pip3 install pytest numpy Pillow pytesseract

    mkdir -p /app
    cd /app

    cat << 'EOF' > generate_image.py
from PIL import Image, ImageDraw, ImageFont
import os

img = Image.new('RGB', (400, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)

text = "Prior Covariance Matrix:\n[[2.0, 0.8]\n [0.8, 3.0]]"
d.text((20, 50), text, fill=(0,0,0))
img.save('/app/target_cov.png')
EOF
    python3 generate_image.py

    cat << 'EOF' > generate_data.py
import numpy as np

np.random.seed(42)
true_mu = [5.5, -2.3]
cov = [[2.0, 0.8], [0.8, 3.0]]
data = np.random.multivariate_normal(true_mu, cov, 500)

with open('/app/sequence_features.csv', 'w') as f:
    f.write("centrality,motif_freq\n")
    for row in data:
        f.write(f"{row[0]:.6f},{row[1]:.6f}\n")
EOF
    python3 generate_data.py

    cat << 'EOF' > /app/verify.py
import numpy as np
import sys
import math

def get_analytical_posterior():
    # Read data
    data = np.loadtxt('/app/sequence_features.csv', delimiter=',', skiprows=1)
    N = len(data)
    x_bar = np.mean(data, axis=0)

    # Setup matrices
    Sigma = np.array([[2.0, 0.8], [0.8, 3.0]])
    Lambda = np.linalg.inv(Sigma)

    mu_0 = np.array([0.0, 0.0])
    Lambda_0 = np.linalg.inv(np.array([[10.0, 0.0], [0.0, 10.0]]))

    # Posterior precision and mean
    Lambda_n = Lambda_0 + N * Lambda
    mu_n = np.linalg.inv(Lambda_n).dot(Lambda_0.dot(mu_0) + N * Lambda.dot(x_bar))
    return mu_n

try:
    with open('/home/user/posterior_mean.txt', 'r') as f:
        content = f.read().strip().split()
        agent_mu = np.array([float(content[0]), float(content[1])])
except Exception as e:
    print(f"Error reading agent output: {e}")
    sys.exit(1)

true_mu_n = get_analytical_posterior()
dist = np.linalg.norm(agent_mu - true_mu_n)

print(f"Distance: {dist:.6f}")
if dist <= 0.05:
    sys.exit(0)
else:
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
