#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy scikit-learn scipy

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data
cat << 'EOF' > /home/user/data/setup.py
import pandas as pd
import numpy as np

np.random.seed(42)

# text.csv
n_texts = 50
t_ids = [f"T{i:03d}" for i in range(n_texts)]
queries = ["apple red " + str(i) for i in range(10)] + \
          ["banana yellow " + str(i) for i in range(10)] + \
          ["grape green " + str(i) for i in range(10)] + \
          ["orange bright " + str(i) for i in range(20)]
docs = ["this is a document about " + q for q in queries]

df_text = pd.DataFrame({"t_id": t_ids, "text_query": queries, "doc_content": docs})
df_text.to_csv("/home/user/data/text.csv", index=False)

# stats.csv
s_ids = [f"S{i:03d}" for i in range(30)]
# some exact matches, some typos
fuzzy = ["aple red " + str(i) for i in range(10)] + \
        ["banan yelow " + str(i) for i in range(10)] + \
        ["grapp gren " + str(i) for i in range(10)]
val_A = np.random.rand(30) * 10
val_B = np.random.rand(30) * 5
target = val_A * val_B * 2.5 + np.random.randn(30)

df_stats = pd.DataFrame({"s_id": s_ids, "fuzzy_query": fuzzy, "val_A": val_A, "val_B": val_B, "target": target})
df_stats.to_csv("/home/user/data/stats.csv", index=False)
EOF

python3 /home/user/data/setup.py
rm /home/user/data/setup.py

chmod -R 777 /home/user
