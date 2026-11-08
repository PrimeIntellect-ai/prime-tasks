#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd

primary_data = {
    'record_id': [5011, 5012, 5013, 5014, 5015, 5016],
    'description': [
        "Analyzing sparse matrices for NLP",
        "Deep convolutional networks for image processing",
        "Analyzing sparse matrices for natural language",
        "Graph neural networks for social network analysis",
        "Recurrent networks for time series forecasting",
        "Basic linear algebra subprograms for optimization"
    ],
    'link_code': ['X1', 'X2', 'X3', 'Y1', 'Y2', 'Y3']
}

secondary_data = {
    'link_code': ['X1', 'X3', 'Y1'],
    'extra_notes': [
        "Focus on TF-IDF tokenization",
        "Focus on TF-IDF tokenization",
        "Using PyTorch Geometric"
    ]
}

df_primary = pd.DataFrame(primary_data)
df_secondary = pd.DataFrame(secondary_data)

df_primary.to_csv('/home/user/primary.csv', index=False)
df_secondary.to_csv('/home/user/secondary.csv', index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
