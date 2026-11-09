#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install --no-cache-dir pytest numpy pandas

    mkdir -p /home/user/spectroscopy_project
    cd /home/user/spectroscopy_project

    cat << 'EOF' > generate_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
x = np.linspace(0, 10, 100)
# True parameters: mu=5.0, sigma=1.2
true_y = np.exp(-0.5 * ((x - 5.0) / 1.2)**2) / (1.2 * np.sqrt(2 * np.pi))
# Add noise and normalize to make it a valid probability distribution for KL divergence
noisy_y = true_y + np.random.normal(0, 0.01, size=len(x))
noisy_y = np.clip(noisy_y, 1e-8, None)
noisy_y /= np.sum(noisy_y)

pd.DataFrame({'x': x, 'y': noisy_y}).to_csv('data.csv', index=False)
EOF

    cat << 'EOF' > loss.py
import sys
import numpy as np
import pandas as pd

if len(sys.argv) != 3:
    print("Usage: python loss.py <mu> <sigma>")
    sys.exit(1)

mu = float(sys.argv[1])
sigma = float(sys.argv[2])

if sigma <= 0:
    print("NaN NaN NaN")
    sys.exit(0)

df = pd.read_csv('data.csv')
x = df['x'].values
y_obs = df['y'].values

# Model
y_mod = np.exp(-0.5 * ((x - mu) / sigma)**2) / (sigma * np.sqrt(2 * np.pi))
y_mod = np.clip(y_mod, 1e-8, None)
y_mod /= np.sum(y_mod)

# KL Divergence
loss = np.sum(y_obs * np.log(y_obs / y_mod))

# Numerical Gradients
eps = 1e-5
# grad mu
y_mod_mu1 = np.exp(-0.5 * ((x - (mu + eps)) / sigma)**2) / (sigma * np.sqrt(2 * np.pi))
y_mod_mu1 = np.clip(y_mod_mu1, 1e-8, None); y_mod_mu1 /= np.sum(y_mod_mu1)
loss_mu1 = np.sum(y_obs * np.log(y_obs / y_mod_mu1))
grad_mu = (loss_mu1 - loss) / eps

# grad sigma
y_mod_sig1 = np.exp(-0.5 * ((x - mu) / (sigma + eps))**2) / ((sigma + eps) * np.sqrt(2 * np.pi))
y_mod_sig1 = np.clip(y_mod_sig1, 1e-8, None); y_mod_sig1 /= np.sum(y_mod_sig1)
loss_sig1 = np.sum(y_obs * np.log(y_obs / y_mod_sig1))
grad_sigma = (loss_sig1 - loss) / eps

print(f"{loss} {grad_mu} {grad_sigma}")
EOF

    cat << 'EOF' > optimize.sh
#!/bin/bash
# A naive gradient descent that diverges
mu=4.0
sigma=1.0
lr=2.0

for i in {1..10}; do
    out=$(python3 loss.py $mu $sigma)
    loss=$(echo $out | awk '{print $1}')
    grad_mu=$(echo $out | awk '{print $2}')
    grad_sigma=$(echo $out | awk '{print $3}')

    echo "Iter $i: mu=$mu, sigma=$sigma, loss=$loss"

    mu=$(awk -v m=$mu -v lr=$lr -v g=$grad_mu 'BEGIN {print m - lr * g}')
    sigma=$(awk -v s=$sigma -v lr=$lr -v g=$grad_sigma 'BEGIN {print s - lr * g}')
done

echo "mu=$mu" > results.txt
echo "sigma=$sigma" >> results.txt
echo "loss=$loss" >> results.txt
EOF

    cat << 'EOF' > pipeline.sh
#!/bin/bash
echo "Generating data..."
python3 generate_data.py
echo "Running optimization..."
bash optimize.sh
echo "Done."
EOF

    chmod +x optimize.sh pipeline.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
