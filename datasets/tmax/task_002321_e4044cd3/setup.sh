#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest jupyter nbconvert nbformat

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_notebook.py
import nbformat as nbf
nb = nbf.v4.new_notebook()
code = """
with open('/home/user/raw_scores.txt', 'w') as f:
    f.write("1000000000.001\\n1000000000.002\\n1000000000.001\\n1000000000.003\\n")
"""
nb['cells'] = [nbf.v4.new_code_cell(code)]
nbf.write(nb, '/home/user/generate_scores.ipynb')
EOF
    python3 /tmp/setup_notebook.py

    echo "0.000001" > /home/user/reference_variance.txt

    chmod -R 777 /home/user
