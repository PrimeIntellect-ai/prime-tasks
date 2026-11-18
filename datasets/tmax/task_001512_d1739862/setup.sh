#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
import unicodedata

# 1. Generate Raw Data
np.random.seed(42)
dates = pd.date_range(start="2023-01-01", end="2023-01-10")
products = {
    "P001": "Caf\u00e9",  # NFC
    "P002": "Cafe\u0301", # NFD
    "P003": "\uFF21\uFF30\uFF30\uFF2C\uFF25", # Fullwidth APPLE
    "P004": "\u304b\u3099", # Decomposed Hiragana 'ga'
}

data = []
for d in dates:
    for pid, pname in products.items():
        row = {
            "Date": d.strftime("%Y-%m-%d"),
            "Product_ID": pid,
            "Product_Name_Local": pname,
            "Sales_NA": np.random.randint(10, 100),
            "Temp_NA": 10.0 + np.random.normal(0, 2),
            "Sales_EU": np.random.randint(5, 50),
            "Temp_EU": 5.0 + np.random.normal(0, 2),
            "Sales_AS": np.random.randint(20, 200),
            "Temp_AS": 15.0 + np.random.normal(0, 2)
        }
        data.append(row)

df = pd.DataFrame(data)

# Introduce missing values for Temp
# e.g., index 5, 12, 25 for NA, EU, AS respectively
df.loc[df.index % 7 == 0, 'Temp_NA'] = np.nan
df.loc[df.index % 5 == 0, 'Temp_EU'] = np.nan
df.loc[df.index % 9 == 0, 'Temp_AS'] = np.nan

df.to_csv("/home/user/raw_sales.csv", index=False)
EOF

python3 /tmp/generate_data.py
rm /tmp/generate_data.py

chmod -R 777 /home/user
