#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_pdb.py
with open('/home/user/input.pdb', 'w') as f:
    for i in range(50):
        z = float(i)
        b = 10.0 + 0.5 * z
        f.write(f"ATOM  {i+1:5d}  CA  ALA A{i+1:4d}    {10.0:8.3f}{10.0:8.3f}{z:8.3f}  1.00{b:6.2f}           C\n")
EOF
    python3 /home/user/generate_pdb.py

    chmod -R 777 /home/user
