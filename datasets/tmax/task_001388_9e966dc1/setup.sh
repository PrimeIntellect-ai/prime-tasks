#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tesseract-ocr fonts-dejavu
    pip3 install pytest numpy pandas scikit-learn pillow

    mkdir -p /app

    # Generate data.csv
    python3 -c "
import numpy as np
import pandas as pd
np.random.seed(42)
data = np.random.randn(100, 10) * 100
pd.DataFrame(data).to_csv('/app/data.csv', index=False, header=False)
"

    # Generate plot_config.png using PIL to avoid ImageMagick policy issues
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (800, 200), color='white')
d = ImageDraw.Draw(img)
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 24)
d.text((20,50), 'Scaling: MaxAbs. Dimensions: 3. Output: /app/reduced.csv', fill='black', font=font)
img.save('/app/plot_config.png')
"

    # Generate ref.csv
    python3 -c "
import numpy as np
import pandas as pd
from sklearn.decomposition import PCA

data = pd.read_csv('/app/data.csv', header=None).values
scaled_data = data / np.max(np.abs(data), axis=0)

pca = PCA(n_components=3)
reduced = pca.fit_transform(scaled_data)

pd.DataFrame(reduced).to_csv('/app/ref.csv', index=False, header=False)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
