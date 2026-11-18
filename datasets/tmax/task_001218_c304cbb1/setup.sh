#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        libtesseract-dev \
        fonts-liberation

    pip3 install pytest pandas scikit-learn numpy flask fastapi uvicorn pytesseract Pillow requests

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Generate CSV
np.random.seed(42)
n = 1000
area = np.random.uniform(500, 5000, n)
age = np.random.uniform(0, 100, n)
income = np.random.uniform(20000, 200000, n)

t_area = area * 0.95
t_age = (age - 2) * 1.1
t_income = (income - income.mean()) / income.std()

price = 50000 + 100 * t_area - 500 * t_age + 20000 * t_income + np.random.normal(0, 10000, n)

df = pd.DataFrame({'Area': area, 'Age': age, 'Income': income, 'Price': price})
df.to_csv('/app/raw_housing_data.csv', index=False)

# Generate Image
img = Image.new('RGB', (1000, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "Transform Area by multiplying by 0.95. Transform Age by subtracting 2 and then multiplying by 1.1."
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 20)
except IOError:
    font = ImageFont.load_default()
d.text((10, 40), text, fill=(0, 0, 0), font=font)
img.save('/app/scaling_rules.png')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
