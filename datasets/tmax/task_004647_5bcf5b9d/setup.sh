#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy scikit-learn pyinstaller

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.py
import sys
import h5py
import numpy as np
from sklearn.decomposition import PCA
from sklearn.preprocessing import QuantileTransformer

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    in_file = sys.argv[1]
    out_file = sys.argv[2]

    with h5py.File(in_file, 'r') as f:
        data = f['raw_features'][:]

    pca = PCA(n_components=5)
    data_pca = pca.fit_transform(data)

    n_quantiles = min(len(data), 1000)
    if n_quantiles < 2:
        n_quantiles = len(data)

    qt = QuantileTransformer(n_quantiles=n_quantiles, output_distribution='uniform')
    data_clean = qt.fit_transform(data_pca)

    with h5py.File(out_file, 'w') as f:
        f.create_dataset('clean_features', data=data_clean)

if __name__ == '__main__':
    main()
EOF

    cd /tmp
    pyinstaller --onefile oracle.py
    mv dist/oracle /app/oracle_processor
    chmod +x /app/oracle_processor
    rm -rf build dist oracle.py oracle.spec

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
