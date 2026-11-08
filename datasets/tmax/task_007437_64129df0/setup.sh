#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import pickle
from sklearn.feature_extraction.text import TfidfVectorizer
import os

# 1. Create products.csv
products_data = {
    'product_id': ['p101', 'p102', 'p103', 'p104', 'p105', 'p106', 'p107', 'p108'],
    'description': [
        'premium organic green tea leaves',
        'premium organic black tea leaves',
        'wireless bluetooth noise cancelling headphones',
        'wired noise isolating earbuds',
        'heavy duty stainless steel cookware set',
        'non-stick aluminum cookware frying pan',
        'mens running shoes athletic sneakers',
        'womens trail running shoes athletic'
    ]
}
products_df = pd.DataFrame(products_data)
products_df.to_csv('/home/user/products.csv', index=False)

# 2. Create history.csv
history_data = {
    'user_id': ['user_1', 'user_42', 'user_42', 'user_99', 'user_42'],
    'product_id': ['p103', 'p101', 'p105', 'p108', 'p107']
}
history_df = pd.DataFrame(history_data)
history_df.to_csv('/home/user/history.csv', index=False)

# 3. Create vectorizer.pkl
vectorizer = TfidfVectorizer()
vectorizer.fit(products_df['description'])
with open('/home/user/vectorizer.pkl', 'wb') as f:
    pickle.dump(vectorizer, f)

EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
