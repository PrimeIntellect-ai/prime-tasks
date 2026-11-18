#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    python3 -c "
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)
N_train = 100
N_test = 50
features = 256

base_0 = np.random.dirichlet(np.ones(features))
base_1 = np.random.dirichlet(np.ones(features))
base_1 = 0.8 * base_1 + 0.2 * base_0

X_train = np.zeros((N_train, features))
y_train = np.random.randint(0, 2, N_train)
for i in range(N_train):
    if y_train[i] == 0:
        X_train[i] = np.random.multinomial(1000, base_0)
    else:
        X_train[i] = np.random.multinomial(1000, base_1)

X_test = np.zeros((N_test, features))
y_test = np.random.randint(0, 2, N_test)
for i in range(N_test):
    if y_test[i] == 0:
        X_test[i] = np.random.multinomial(1000, base_0)
    else:
        X_test[i] = np.random.multinomial(1000, base_1)

np.save('/home/user/kmer_train.npy', X_train)
np.save('/home/user/labels_train.npy', y_train)
np.save('/home/user/kmer_test.npy', X_test)
np.save('/home/user/labels_test.npy', y_test)
"

    chmod -R 777 /home/user
