#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest numpy pandas

mkdir -p /home/user/data

cat << 'EOF' > /home/user/setup_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
n_samples = 100
ids = np.arange(1, n_samples + 1)
np.random.shuffle(ids)

# Generate features
f1 = np.random.randn(n_samples) * 2 + 5
f2 = np.random.randn(n_samples) * 0.5 - 2
f3 = np.random.randn(n_samples) * 10

# Generate target
target = 3.5 * (f1 - 5)/2 - 1.2 * (f2 + 2)/0.5 + 0.8 * (f3)/10 + np.random.randn(n_samples) * 0.5

# Create DataFrames
df_features = pd.DataFrame({'id': ids, 'f1': f1, 'f2': f2, 'f3': f3})
df_targets = pd.DataFrame({'id': ids, 'target': target})

# Shuffle targets differently to test join
df_targets = df_targets.sample(frac=1, random_state=123).reset_index(drop=True)

df_features.to_csv('/home/user/data/features.csv', index=False)
df_targets.to_csv('/home/user/data/targets.csv', index=False)
EOF

python3 /home/user/setup_data.py
rm /home/user/setup_data.py

cat << 'EOF' > /home/user/verify.py
import numpy as np
import pandas as pd

df_features = pd.read_csv('/home/user/data/features.csv')
df_targets = pd.read_csv('/home/user/data/targets.csv')

df = pd.merge(df_features, df_targets, on='id', how='inner').sort_values('id').reset_index(drop=True)

mses = []
fold_size = len(df) // 5

for i in range(5):
    val_idx = list(range(i * fold_size, (i + 1) * fold_size))
    train_idx = [idx for idx in range(len(df)) if idx not in val_idx]

    train_data = df.iloc[train_idx]
    val_data = df.iloc[val_idx]

    train_f = train_data[['f1', 'f2', 'f3']].values
    val_f = val_data[['f1', 'f2', 'f3']].values
    train_t = train_data['target'].values
    val_t = val_data['target'].values

    # Calculate stats
    means = np.mean(train_f, axis=0)
    stds = np.std(train_f, axis=0, ddof=0)

    train_f_norm = (train_f - means) / stds
    val_f_norm = (val_f - means) / stds

    # Correlations
    corrs = []
    for col in range(3):
        f_col = train_f_norm[:, col]
        corr = np.corrcoef(f_col, train_t)[0, 1]
        corrs.append(corr)

    w = np.array(corrs)
    val_preds = np.dot(val_f_norm, w)

    mse = np.mean((val_preds - val_t) ** 2)
    mses.append(mse)

avg_mse = np.mean(mses)
with open('/tmp/expected_mse.txt', 'w') as f:
    f.write(f"{avg_mse:.4f}")
EOF

python3 /home/user/verify.py

cat << 'EOF' > /home/user/check.sh
#!/bin/bash
if [ ! -f /home/user/final_mse.txt ]; then
    echo "Failure: /home/user/final_mse.txt not found."
    exit 1
fi

EXPECTED=$(cat /tmp/expected_mse.txt)
ACTUAL=$(cat /home/user/final_mse.txt)

python3 -c "
import sys
expected = float('$EXPECTED')
actual = float('$ACTUAL')
if abs(expected - actual) > 0.1:
    print(f'Failure: Expected {expected}, got {actual}')
    sys.exit(1)
else:
    print('Success')
    sys.exit(0)
"
EOF
chmod +x /home/user/check.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
