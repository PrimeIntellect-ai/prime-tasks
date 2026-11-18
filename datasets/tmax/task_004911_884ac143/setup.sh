#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv tesseract-ocr
pip3 install pytest pandas numpy Pillow

mkdir -p /home/user/planner/data
mkdir -p /home/user/planner/output
mkdir -p /home/user/verifier
mkdir -p /app

# Create the dashboard image using Pillow
cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw

img = Image.new('RGB', (800, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "System Planning Parameters: Growth Factor: 1.05. Weekend Discount: 0.80."
d.text((10, 40), text, fill=(0, 0, 0))
img.save('/app/dashboard_multipliers.png')
EOF
python3 /tmp/gen_img.py

# Create history.csv
cat << 'EOF' > /tmp/generate_history.py
import pandas as pd
import numpy as np

# Day 1 is Monday.
days = np.arange(1, 101)
# Base load is a linear trend
base_load = 50 + 0.5 * days
# Weekend discount: Day 6, 7, 13, 14, etc. (day % 7 == 6 or day % 7 == 0)
is_weekend = (days % 7 == 6) | (days % 7 == 0)
load = base_load.copy()
load[is_weekend] = base_load[is_weekend] * 0.80
# Add some noise
np.random.seed(42)
load += np.random.normal(0, 1.5, size=len(days))

df = pd.DataFrame({'day': days, 'cpu_load': load})
df.to_csv('/home/user/planner/data/history.csv', index=False)
EOF
python3 /tmp/generate_history.py

# Create evaluate.py
cat << 'EOF' > /home/user/verifier/evaluate.py
import pandas as pd
import numpy as np

# Generate true future data (days 101 to 130)
days = np.arange(101, 131)
base_load = 50 + 0.5 * days
# Apply growth factor from image (1.05) to the base trend
base_load = base_load * 1.05

is_weekend = (days % 7 == 6) | (days % 7 == 0)
true_load = base_load.copy()
true_load[is_weekend] = base_load[is_weekend] * 0.80

try:
    pred_df = pd.read_csv('/home/user/planner/output/forecast.csv')
    if not {'day', 'predicted_load'}.issubset(pred_df.columns):
        print("Missing required columns.")
        exit(1)

    pred_df = pred_df.sort_values('day')
    if len(pred_df) != 30:
        print(f"Expected 30 predictions, got {len(pred_df)}")
        exit(1)

    mse = np.mean((pred_df['predicted_load'].values - true_load) ** 2)
    print(f"MSE: {mse}")
    if mse < 2.0:
        print("PASS")
        exit(0)
    else:
        print("FAIL")
        exit(1)
except Exception as e:
    print(f"Error evaluating: {e}")
    exit(1)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
