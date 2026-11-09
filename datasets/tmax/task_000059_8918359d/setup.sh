#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest mlflow scikit-learn pandas scipy

    mkdir -p /home/user/pipeline
    mkdir -p /home/user/mlruns

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
np.random.seed(42)
n_samples = 500
df = pd.DataFrame({
    'feature_1': np.random.normal(10, 2, n_samples),
    'feature_2': np.random.normal(5, 1, n_samples),
    'feature_3': np.random.normal(0, 5, n_samples)
})
# Inject missing values and outliers
df.loc[10:20, 'feature_1'] = np.nan
df.loc[40:50, 'feature_2'] = 100.0 # outlier
df['target_engagement'] = 3.0 * df['feature_1'].fillna(10) - 1.5 * df['feature_2'] + np.random.normal(0, 1, n_samples)
df.to_csv('/home/user/pipeline/data.csv', index=False)
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    cat << 'EOF' > /home/user/pipeline/train.py
import pandas as pd
import numpy as np
import mlflow
from sklearn.model_selection import train_test_split
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error
import scipy.stats as stats

RANDOM_STATE = 42

def main():
    mlflow.set_tracking_uri("http://127.0.0.1:5000")
    mlflow.set_experiment("engagement_prediction")

    with mlflow.start_run() as run:
        # Load data
        df = pd.read_csv("data.csv")
        X = df[['feature_1', 'feature_2', 'feature_3']]
        y = df['target_engagement']

        # DATA LEAKAGE: Imputing and scaling before split
        imputer = SimpleImputer(strategy='mean')
        X_imputed = imputer.fit_transform(X)

        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X_imputed)

        # Train/test split
        X_train, X_test, y_train, y_test = train_test_split(
            X_scaled, y, test_size=0.2, random_state=RANDOM_STATE
        )

        # Train model
        model = Ridge(alpha=1.0, random_state=RANDOM_STATE)
        model.fit(X_train, y_train)

        # Evaluate
        preds = model.predict(X_test)
        mse = mean_squared_error(y_test, preds)
        mlflow.log_metric("mse", mse)

        # Log correlation matrix
        corr_matrix = pd.DataFrame(X_scaled).corr()
        corr_matrix.to_csv("corr_matrix.csv", index=False)
        mlflow.log_artifact("corr_matrix.csv")

        print("Run complete.")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
