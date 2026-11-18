#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest pandas scikit-learn numpy scipy statsmodels patsy

    # Vendor category_encoders
    mkdir -p /app
    git clone --branch 2.6.3 https://github.com/scikit-learn-contrib/category_encoders.git /app/category_encoders

    # Introduce bug
    sed -i 's/import numpy as np/import numpy as npp/g' /app/category_encoders/category_encoders/target_encoder.py

    # Create user and data dir
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    # Generate data
    cat << 'EOF' > /tmp/gen_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_samples = 1000

jobs = ['engineer', 'doctor', 'teacher', 'clerk', 'manager']
cities = ['NY', 'LA', 'SF', 'CHI', 'MIA']

age = np.random.randint(20, 65, n_samples)
hours = np.random.randint(20, 60, n_samples)
job = np.random.choice(jobs, n_samples)
city = np.random.choice(cities, n_samples)

# Make some data messy
job_messy = [j + ('_typo' if np.random.rand() < 0.1 else '') for j in job]
city_messy = [c.lower() if np.random.rand() < 0.2 else c for c in city]

job_income = {'engineer': 80000, 'doctor': 120000, 'teacher': 50000, 'clerk': 40000, 'manager': 90000}
city_income = {'NY': 20000, 'LA': 10000, 'SF': 30000, 'CHI': 5000, 'MIA': 0}

income = [job_income[j] + city_income[c] + a * 500 + h * 200 + np.random.normal(0, 5000) for j, c, a, h in zip(job, city, age, hours)]

df = pd.DataFrame({'age': age, 'hours_per_week': hours, 'job_title': job_messy, 'city': city_messy, 'income': income})

df_train = df.iloc[:800]
df_test = df.iloc[800:]

df_train.to_csv('/home/user/data/train.csv', index=False)
df_test.drop(columns=['income']).to_csv('/home/user/data/test.csv', index=False)
df_test[['income']].to_csv('/home/user/data/test_labels.csv', index=False)
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    chmod -R 777 /home/user
    chmod -R 777 /app/category_encoders
