#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        redis-server \
        nginx \
        build-essential \
        libfftw3-dev \
        libhdf5-dev \
        python3-scipy \
        python3-numpy \
        python3-h5py \
        python3-flask \
        curl \
        jq

    pip3 install --no-cache-dir pytest redis

    mkdir -p /app/services/api
    mkdir -p /app/services/nginx
    mkdir -p /home/user/src
    mkdir -p /home/user/bin
    mkdir -p /app/data/clean
    mkdir -p /app/data/evil

    # Create app.py
    cat << 'EOF' > /app/services/api/app.py
from flask import Flask, request, jsonify
import scipy.stats as stats
import numpy as np

app = Flask(__name__)

@app.route('/api/analyze_spectrum', methods=['POST'])
def analyze():
    data = request.json.get('spectrum', [])
    if not data:
        return jsonify({'p_value': 1.0})
    z = (np.max(data) - np.mean(data)) / (np.std(data) + 1e-9)
    p = stats.norm.sf(z)
    return jsonify({'p_value': p})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create nginx.conf with deliberate bug
    cat << 'EOF' > /app/services/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/ {
            proxy_pass http://127.0.0.1:5001/;
        }
    }
}
EOF

    # Create startup script
    cat << 'EOF' > /app/services/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/services/nginx/nginx.conf
cd /app/services/api
nohup python3 app.py > api.log 2>&1 &
EOF
    chmod +x /app/services/start_services.sh

    # Create C source code
    cat << 'EOF' > /home/user/src/calc_spectrum.c
#include <stdio.h>
#include <stdlib.h>
#include <hdf5.h>
#include <fftw3.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    hid_t file_id = H5Fopen(argv[1], H5F_ACC_RDONLY, H5P_DEFAULT);
    if (file_id < 0) return 1;
    hid_t dataset_id = H5Dopen(file_id, "/sequence", H5P_DEFAULT);
    if (dataset_id < 0) return 1;

    double data[1024];
    H5Dread(dataset_id, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, data);
    H5Dclose(dataset_id);
    H5Fclose(file_id);

    fftw_complex *out = (fftw_complex*) fftw_malloc(sizeof(fftw_complex) * 1024);
    fftw_plan p = fftw_plan_dft_r2c_1d(1024, data, out, FFTW_ESTIMATE);
    fftw_execute(p);

    for (int i = 0; i < 513; i++) {
        double power = out[i][0]*out[i][0] + out[i][1]*out[i][1];
        printf("%f%s", power, i == 512 ? "" : ",");
    }
    printf("\n");

    fftw_destroy_plan(p);
    fftw_free(out);
    return 0;
}
EOF

    # Generate HDF5 data files
    cat << 'EOF' > /tmp/gen_data.py
import h5py
import numpy as np
import os

for i in range(5):
    with h5py.File(f'/app/data/clean/seq_{i}.h5', 'w') as f:
        f.create_dataset('/sequence', data=np.random.randn(1024))

    with h5py.File(f'/app/data/evil/seq_{i}.h5', 'w') as f:
        t = np.arange(1024)
        data = np.random.randn(1024) + 5 * np.sin(2 * np.pi * 0.1 * t)
        f.create_dataset('/sequence', data=data)
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
