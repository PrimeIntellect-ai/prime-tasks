#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    python3 -c "
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

data_a = {
    'id': ['A1', 'A2', 'A3', 'A4', 'A5'],
    'desc': [
        'Red shiny apple fruit',
        'Green banana bunch',
        'Fresh orange juice bottle',
        'Whole wheat bread loaf',
        'Organic whole milk gallon'
    ],
    'price': [1.20, np.nan, 3.50, 2.50, 4.00],
    'rating': [4.5, 3.0, np.nan, 4.2, 4.8]
}

data_b = {
    'id': ['B1', 'B2', 'B3', 'B4', 'B5', 'B6'],
    'desc': [
        'Apple red and shiny',
        'Orange juice freshly squeezed',
        'Bananas green unripe',
        'Rotten tomato',
        'Milk gallon organic whole',
        'Loaf of whole wheat bread'
    ],
    'price': [1.10, 3.00, 2.00, 0.50, np.nan, 2.20],
    'rating': [4.2, 4.8, 3.5, 1.0, 4.5, 4.0]
}

df_a = pd.DataFrame(data_a)
df_b = pd.DataFrame(data_b)

df_a.to_csv('/home/user/supplier_a.csv', index=False)
df_b.to_csv('/home/user/supplier_b.csv', index=False)
"

    chmod -R 777 /home/user
