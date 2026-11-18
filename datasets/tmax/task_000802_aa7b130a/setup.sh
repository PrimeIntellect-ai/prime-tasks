#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libgl1 libglib2.0-0
    pip3 install pytest opencv-python numpy joblib

    mkdir -p /app
    cat << 'EOF' > /app/setup.py
import os
import cv2
import numpy as np
import random

os.makedirs('/app', exist_ok=True)

# Generate texts.csv and labels
texts = []
labels = []
positive_words = ["good", "great", "excellent", "amazing", "wonderful", "fantastic", "superb"]
negative_words = ["bad", "terrible", "awful", "horrible", "poor", "disgusting", "useless"]

random.seed(42)
for _ in range(1000):
    if random.random() > 0.5:
        text = f"This product is {random.choice(positive_words)} and I love it."
        labels.append(1)
    else:
        text = f"This product is {random.choice(negative_words)} and I hate it."
        labels.append(0)
    texts.append(text)

with open('/app/texts.csv', 'w') as f:
    for text in texts:
        f.write(text + '\n')

# Generate labels.mp4
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/labels.mp4', fourcc, 10.0, (100, 100))

for label in labels:
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    if label == 1:
        frame[:] = (0, 255, 0) # Green (BGR)
    else:
        frame[:] = (0, 0, 255) # Red (BGR)
    out.write(frame)

out.release()

# Generate plot_results.py
plot_script = """import matplotlib.pyplot as plt
import numpy as np

# Intentional bug: backend requires interactive display, saving might be blank if not set properly in some environments, or we just call show() before savefig()
# To fix, the agent should set matplotlib.use('Agg') and remove plt.show() or swap order.

def generate_plot():
    x = np.arange(10)
    y = np.random.rand(10)
    plt.plot(x, y)
    plt.show() # Consumes the figure
    plt.savefig('/home/user/cv_results.png')

if __name__ == '__main__':
    generate_plot()
"""
with open('/app/plot_results.py', 'w') as f:
    f.write(plot_script)
EOF

    python3 /app/setup.py
    rm /app/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
