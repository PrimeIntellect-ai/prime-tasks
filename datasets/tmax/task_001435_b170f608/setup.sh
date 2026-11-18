#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scipy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

cat << 'EOF' > /home/user/data.csv
id,text
1,hello world
2,testing embeddings here
,missing id row
3,another text
4,foo bar baz
5,short
,another missing
6,a bit longer text for group B
EOF

cat << 'EOF' > /home/user/metadata.csv
id,group
1,A
2,A
3,B
4,B
5,A
6,B
EOF

cat << 'EOF' > /home/user/preprocess.py
import pandas as pd

df = pd.read_csv('/home/user/data.csv')
# Simple embedding: text length
df['embedding'] = df['text'].apply(lambda x: len(str(x)))

# The bug: The df is saved without dropping NaNs or casting id to int
df[['id', 'embedding']].to_csv('/home/user/processed_data.csv', index=False)
EOF

cat << 'EOF' > /home/user/ttest.py
import pandas as pd
import sys
from scipy import stats

try:
    df = pd.read_csv(sys.argv[1], header=None, names=['id', 'embedding', 'group'])
    if df.empty:
        print("p-value: NaN")
        sys.exit(0)

    group_a = df[df['group'] == 'A']['embedding']
    group_b = df[df['group'] == 'B']['embedding']

    t, p = stats.ttest_ind(group_a, group_b)
    print(f"p-value: {p}")
except Exception as e:
    print("p-value: NaN")
EOF

cat << 'EOF' > /home/user/pipeline.sh
#!/bin/bash
cd /home/user

# 1. Preprocess data
python3 preprocess.py

# 2. Sort processed data (skip header)
tail -n +2 processed_data.csv | sort -t, -k1,1 > sorted_processed.csv

# 3. Sort metadata (skip header)
tail -n +2 metadata.csv | sort -t, -k1,1 > sorted_metadata.csv

# 4. Join on ID (column 1 in both files)
join -t, -1 1 -2 1 sorted_processed.csv sorted_metadata.csv > joined.csv

# 5. Run T-Test
python3 ttest.py joined.csv > results.txt
EOF

    chmod +x /home/user/pipeline.sh
    chmod -R 777 /home/user
