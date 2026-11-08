#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest scikit-learn numpy

mkdir -p /home/user/ml_pipeline
cd /home/user/ml_pipeline

cat << 'EOF' > generate_data.py
import random
random.seed(42)
with open('users.csv', 'w') as f1, open('transactions.csv', 'w') as f2:
    for i in range(1, 1001):
        user_id = f"{i:04d}"
        age = random.randint(18, 80)
        amount = round(random.uniform(5.0, 500.0), 2)
        fraud = 1 if amount > 400 and age < 25 else 0
        f1.write(f"{user_id},{age}\n")
        f2.write(f"{user_id},{amount},{fraud}\n")
EOF

cat << 'EOF' > prepare_data.sh
#!/bin/bash
# Buggy script: Data leakage!
join -t, -1 1 -2 1 <(sort -t, -k1,1 users.csv) <(sort -t, -k1,1 transactions.csv) > joined.csv
# computes min max on EVERYTHING
MIN=$(awk -F, 'NR==1{min=$3} {if($3<min) min=$3} END{print min}' joined.csv)
MAX=$(awk -F, 'NR==1{max=$3} {if($3>max) max=$3} END{print max}' joined.csv)

awk -F, -v min="$MIN" -v max="$MAX" '{
    scaled = ($3 - min) / (max - min);
    printf "%s,%s,%.4f,%s\n", $1, $2, scaled, $4
}' joined.csv > scaled_all.csv

head -n 800 scaled_all.csv > train_scaled.csv
tail -n 200 scaled_all.csv > test_scaled.csv
EOF
chmod +x prepare_data.sh

cat << 'EOF' > train_model.py
import sys
import pickle
import numpy as np
from sklearn.linear_model import LogisticRegression

def load_data(file_path):
    data = np.loadtxt(file_path, delimiter=',')
    return data[:, 1:3], data[:, 3]

X_train, y_train = load_data("train_scaled.csv")
X_test, y_test = load_data("test_scaled.csv")

clf = LogisticRegression(random_state=42)
clf.fit(X_train, y_train)
acc = clf.score(X_test, y_test)
print(f"Test Accuracy: {acc:.4f}")

with open("model.pkl", "wb") as f:
    pickle.dump(clf, f)
EOF

cat << 'EOF' > predict.py
import sys
import pickle
import numpy as np

if len(sys.argv) != 2:
    sys.exit(1)

X_test, _ = np.loadtxt(sys.argv[1], delimiter=',', usecols=(1,2)), np.loadtxt(sys.argv[1], delimiter=',', usecols=3)
with open("model.pkl", "rb") as f:
    clf = pickle.load(f)

preds = clf.predict(X_test)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
