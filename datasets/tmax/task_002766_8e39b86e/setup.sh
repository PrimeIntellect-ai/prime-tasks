#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip docker-compose
pip3 install pytest pandas numpy scikit-learn mlflow joblib boto3 psycopg2-binary

mkdir -p /app
mkdir -p /home/user

cat << 'EOF' > /app/docker-compose.yml
version: '3.8'

services:
  postgres:
    image: postgres:13
    environment:
      - POSTGRES_USER=mlflow
      - POSTGRES_PASSWORD=mlflow
      - POSTGRES_DB=mlflow
    ports:
      - "5432:5432"

  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    environment:
      - MINIO_ROOT_USER=wrong_user
      - MINIO_ROOT_PASSWORD=wrong_password
    ports:
      - "9000:9000"
      - "9001:9001"

  mlflow:
    image: python:3.9-slim
    command: >
      bash -c "pip install mlflow psycopg2-binary boto3 &&
      mlflow server --backend-store-uri postgresql://mlflow:mlflow@postgres:5433/mlflow --default-artifact-root s3://mlflow/ --host 0.0.0.0 --port 5000"
    environment:
      - AWS_ACCESS_KEY_ID=wrong_user
      - AWS_SECRET_ACCESS_KEY=wrong_password
      - MLFLOW_S3_ENDPOINT_URL=http://minio:9005
    ports:
      - "5000:5000"
    depends_on:
      - postgres
      - minio
EOF

cat << 'EOF' > /tmp/gen_data.py
import pandas as pd
import numpy as np
from sklearn.datasets import make_regression

X, y = make_regression(n_samples=2000, n_features=50, n_informative=10, noise=0.1, random_state=42)
mask = np.random.rand(*X.shape) < 0.05
X[mask] = np.nan

df = pd.DataFrame(X, columns=[f'f{i}' for i in range(50)])
df['target'] = y

train = df.iloc[:1000]
test = df.iloc[1000:]

train.to_csv('/home/user/train_data.csv', index=False)
test.to_csv('/app/test_data.csv', index=False)
EOF

python3 /tmp/gen_data.py
rm /tmp/gen_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
