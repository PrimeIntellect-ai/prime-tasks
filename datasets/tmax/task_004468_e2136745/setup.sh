#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest numpy

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import numpy as np
np.random.seed(42)
X = np.random.randn(100, 3) * 2 + 5
y = np.random.randint(0, 2, 100)
with open('embeddings.csv', 'w') as f:
    for i in range(100):
        f.write(f"{X[i,0]:.4f},{X[i,1]:.4f},{X[i,2]:.4f},{y[i]}\n")
EOF
    python3 generate_data.py

    cat << 'EOF' > normalize.sh
#!/bin/bash
awk -F, '
NR==FNR {
    for(i=1;i<=3;i++) {
        if(NR==1 || $i<min[i]) min[i]=$i;
        if(NR==1 || $i>max[i]) max[i]=$i;
    }
    next
}
{
    printf "%.4f,%.4f,%.4f,%d\n", ($1-min[1])/(max[1]-min[1]), ($2-min[2])/(max[2]-min[2]), ($3-min[3])/(max[3]-min[3]), $4
}' embeddings.csv embeddings.csv > normalized.csv

head -n 80 normalized.csv > train.csv
tail -n 20 normalized.csv > test.csv
EOF
    chmod +x normalize.sh

    cat << 'EOF' > evaluate.py
import numpy as np

def load_data(path):
    data = np.loadtxt(path, delimiter=',')
    return data[:, :3], data[:, 3]

X_train, y_train = load_data('train.csv')
X_test, y_test = load_data('test.csv')

# Simple Gaussian Naive Bayes estimation for probability
means = {}
vars = {}
priors = {}

for c in [0, 1]:
    X_c = X_train[y_train == c]
    means[c] = np.mean(X_c, axis=0)
    vars[c] = np.var(X_c, axis=0) + 1e-9
    priors[c] = len(X_c) / len(X_train)

log_probs = []
for x in X_test:
    lp_c = []
    for c in [0, 1]:
        # Log likelihood of x given class c
        ll = -0.5 * np.sum(np.log(2 * np.pi * vars[c])) - 0.5 * np.sum(((x - means[c])**2) / vars[c])
        lp_c.append(ll + np.log(priors[c]))
    log_probs.append(lp_c)

log_probs = np.array(log_probs)
np.savetxt('test_log_probs.txt', log_probs, fmt='%.4f', delimiter=',')
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
