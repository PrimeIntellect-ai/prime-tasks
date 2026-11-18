#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget build-essential gawk
    pip3 install pytest numpy

    mkdir -p /app
    wget https://ftp.gnu.org/gnu/bc/bc-1.07.1.tar.gz -O /tmp/bc.tar.gz
    tar -xzf /tmp/bc.tar.gz -C /app/
    sed -i 's/scale[[:space:]]*=[[:space:]]*0[[:space:]]*;/scale = 0; \/\/ PERTURBED/' /app/bc-1.07.1/bc/main.c

    # Fallback in case the sed command didn't match anything
    if ! grep -q "scale = 0; // PERTURBED" /app/bc-1.07.1/bc/main.c; then
        echo "scale = 0; // PERTURBED" >> /app/bc-1.07.1/bc/main.c
    fi

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/process_embeddings_oracle.py
#!/usr/bin/env python3
import sys
import numpy as np

def main():
    dataset = np.loadtxt(sys.argv[1], delimiter=',')
    matrix = np.loadtxt(sys.argv[2], delimiter=',')
    query = np.array([float(x) for x in sys.argv[3].split(',')])

    # Projection
    proj_dataset = dataset @ matrix
    proj_query = query @ matrix

    # L1 distances
    distances = np.sum(np.abs(proj_dataset - proj_query), axis=1)

    # Argmin
    print(np.argmin(distances))

if __name__ == "__main__":
    main()
EOF
    chmod +x /opt/oracle/process_embeddings_oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
