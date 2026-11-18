#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow matplotlib

    mkdir -p /home/user

    # Create articles.jsonl
    cat << 'EOF' > /home/user/articles.jsonl
{"article_id": "A001", "text": "Data Science is the sexiest job of the 21st century! 100% true."}
{"article_id": "A002", "text": "Python 3.10 brings structural pattern matching."}
{"article_id": "A003", "text": "Transformers revolutionized NLP."}
{"article_id": "A004", "text": "Are large language models AGI? No."}
{"article_id": "A005", "text": "Pandas, PyArrow, and Parquet: A data engineer's toolkit."}
EOF

    # Create metadata.jsonl
    cat << 'EOF' > /home/user/metadata.jsonl
{"article_id": "A001", "source": "HBR"}
{"article_id": "A002", "source": "TechBlog"}
{"article_id": "A003", "source": "Arxiv"}
{"article_id": "A004", "source": "Twitter"}
{"article_id": "A005", "source": "Medium"}
{"article_id": "A006", "source": "Unknown"}
EOF

    # Create the broken plot_distribution.py
    cat << 'EOF' > /home/user/plot_distribution.py
import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_parquet('/home/user/processed_corpus.parquet')

plt.figure(figsize=(8, 6))
plt.hist(df['token_count'], bins=5, color='blue', edgecolor='black')
plt.title('Token Count Distribution')
plt.xlabel('Number of Tokens')
plt.ylabel('Frequency')

# This will fail/hang in a headless environment without X11
plt.show()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/
    chmod -R 777 /home/user
