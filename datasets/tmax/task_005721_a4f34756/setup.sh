#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/create_data.py
import h5py
import numpy as np

# y = 3.5 * x
x = np.linspace(0, 10, 50)
y = 3.5 * x + np.random.normal(0, 0.01, 50)
data = np.column_stack((x, y))

with h5py.File('/home/user/dataset.h5', 'w') as f:
    f.create_dataset('/observations', data=data)
EOF
    python3 /tmp/create_data.py

    cat << 'EOF' > /home/user/fit.sh
#!/bin/bash
# Extract 2D array and format as simple columns
h5dump -y -d /observations -w 1000 /home/user/dataset.h5 | grep -E "^\s*\([0-9]+,0\):" | sed 's/.*: //' | tr -d ',' | awk '
BEGIN { w = 0.0; lr = 0.5; epochs = 200 }
{
    x[NR] = $1;
    y[NR] = $2;
    count = NR;
}
END {
    for (e = 1; e <= epochs; e++) {
        grad = 0;
        for (i = 1; i <= count; i++) {
            pred = w * x[i];
            error = pred - y[i];
            grad += error * x[i];
        }
        w = w - lr * (grad / count);
    }
    printf "%.2f\n", w;
}'
EOF
    chmod +x /home/user/fit.sh

    chmod -R 777 /home/user
