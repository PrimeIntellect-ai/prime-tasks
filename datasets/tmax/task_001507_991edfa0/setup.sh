#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr rustc cargo imagemagick
    pip3 install pytest numpy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate image
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black \
        -draw "text 10,30 'Prior Parameters:'" \
        -draw "text 10,60 'alpha_signal: N(mu=2.5, sigma=0.5)'" \
        -draw "text 10,90 'beta_flux: N(mu=10.0, sigma=2.0)'" \
        -draw "text 10,120 'gamma_resonance: N(mu=-1.2, sigma=0.3)'" \
        /app/model_params.png

    # Generate CSVs
    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np

np.random.seed(42)
n_samples = 1000

def generate_corpus(path, alpha_mu, alpha_sig, beta_mu, beta_sig, gamma_mu, gamma_sig):
    os.makedirs(path, exist_ok=True)

    alpha = np.random.normal(alpha_mu, alpha_sig, n_samples)
    beta = np.random.normal(beta_mu, beta_sig, n_samples)
    gamma = np.random.normal(gamma_mu, gamma_sig, n_samples)

    with open(os.path.join(path, "signals.csv"), "w") as f:
        f.write("instance_id,alpha_signal\n")
        for i in range(n_samples):
            f.write(f"{i},{alpha[i]}\n")

    with open(os.path.join(path, "fluxes.csv"), "w") as f:
        f.write("instance_id,beta_flux\n")
        for i in range(n_samples):
            f.write(f"{i},{beta[i]}\n")

    with open(os.path.join(path, "resonances.csv"), "w") as f:
        f.write("instance_id,gamma_resonance\n")
        for i in range(n_samples):
            f.write(f"{i},{gamma[i]}\n")

generate_corpus("/app/corpus/clean", 2.5, 0.5, 10.0, 2.0, -1.2, 0.3)
generate_corpus("/app/corpus/evil", 2.5, 0.5, 10.0, 2.0, 0.0, 0.8)
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
