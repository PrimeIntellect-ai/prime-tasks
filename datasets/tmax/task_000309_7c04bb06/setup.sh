#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scipy matplotlib flask requests

    mkdir -p /home/user/data
    mkdir -p /app/research-viz-pkg/research_viz

    cat << 'EOF' > /home/user/data/texts.csv
group,text
Control,"Hello, world. This is a simple test!"
Control,"Short words are fun."
Control,"We like to keep things very easy."
Treatment,"Extraordinary, multifaceted vocabulary!"
Treatment,"Considerable complexities emerge."
Treatment,"Sophisticated terminology utilized."
EOF

    cat << 'EOF' > /app/research-viz-pkg/setup.py
from setuptools import setup, find_packages
setup(
    name='research-viz-pkg',
    version='1.0.0',
    packages=find_packages(),
    install_requires=['matplotlib'],
)
EOF

    touch /app/research-viz-pkg/research_viz/__init__.py

    cat << 'EOF' > /app/research-viz-pkg/research_viz/plot_utils.py
import matplotlib
matplotlib.use('Template') # PERTURBATION
import matplotlib.pyplot as plt

def generate_boxplot(control, treatment, output_path):
    fig, ax = plt.subplots()
    ax.boxplot([control, treatment], labels=['Control', 'Treatment'])
    ax.set_ylabel('Mean Token Length')
    plt.savefig(output_path)
    plt.close()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
