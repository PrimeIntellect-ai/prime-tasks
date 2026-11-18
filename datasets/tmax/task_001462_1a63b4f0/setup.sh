#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

    # Install system dependencies
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core

    # Install Python packages
    pip3 install pytest matplotlib numpy

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /app/logs/clean /app/logs/evil

    # Create the experiment metadata image
    # Note: imagemagick may need a font to draw text properly, which is why fonts-dejavu-core is installed
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'MIN_SIMILARITY_SCORE=0.750'" /app/experiment_metadata.png

    # Create the problematic plotting script
    cat << 'EOF' > /home/user/plot_results.py
# /home/user/plot_results.py
import matplotlib
import matplotlib.pyplot as plt
import numpy as np

# Forcing an interactive backend that will fail in headless unless fixed
matplotlib.use('TkAgg') 

plt.plot(np.random.rand(10))
plt.title("Similarity Search CIs")
plt.savefig("/home/user/artifact_plot.png")
EOF

    # Populate Clean Corpus
    cat << 'EOF' > /app/logs/clean/clean_1.json
{"run_id": "c1", "p_value": 0.05, "ci_lower": 0.70, "ci_upper": 0.90, "similarity_score": 0.76}
EOF
    cat << 'EOF' > /app/logs/clean/clean_2.json
{"run_id": "c2", "p_value": 0.99, "ci_lower": -0.1, "ci_upper": 0.1, "similarity_score": 0.88}
EOF
    cat << 'EOF' > /app/logs/clean/clean_3.json
{"run_id": "c3", "p_value": 0.00, "ci_lower": 0.75, "ci_upper": 0.75, "similarity_score": 0.75}
EOF

    # Populate Evil Corpus
    cat << 'EOF' > /app/logs/evil/evil_1.json
{"run_id": "e1", "p_value": 1.05, "ci_lower": 0.70, "ci_upper": 0.90, "similarity_score": 0.80}
EOF
    cat << 'EOF' > /app/logs/evil/evil_2.json
{"run_id": "e2", "p_value": 0.05, "ci_lower": 0.90, "ci_upper": 0.70, "similarity_score": 0.80}
EOF
    cat << 'EOF' > /app/logs/evil/evil_3.json
{"run_id": "e3", "p_value": -0.01, "ci_lower": 0.70, "ci_upper": 0.90, "similarity_score": 0.80}
EOF
    cat << 'EOF' > /app/logs/evil/evil_4.json
{"run_id": "e4", "p_value": 0.50, "ci_lower": 0.70, "ci_upper": 0.90, "similarity_score": 0.749}
EOF

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
