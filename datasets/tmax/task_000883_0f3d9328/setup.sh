#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
temperature,vibration,sensor_type,failure
45.2,0.12,A,0
48.1,,B,0
,0.95,C,1
42.3,0.11,A,0
55.4,0.88,B,1
44.1,,A,0
,,C,1
46.5,0.15,B,0
50.2,0.75,A,1
47.8,0.14,C,0
EOF

    cat << 'EOF' > /home/user/pipeline.py
import pandas as pd
import matplotlib.pyplot as plt
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, f1_score
import json

def clean_data(df):
    # TODO: Impute missing numeric values with median
    # TODO: One-hot encode 'sensor_type'
    pass

def plot_feature_importance(model, feature_names):
    importances = model.feature_importances_
    plt.figure()
    plt.barh(feature_names, importances)
    plt.title('Feature Importances')
    # BUG: This crashes in headless environments
    plt.show()

def train_and_evaluate(df):
    X = df.drop('failure', axis=1)
    y = df['failure']

    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

    model = RandomForestClassifier(random_state=42)
    model.fit(X_train, y_train)

    y_pred = model.predict(X_test)

    # TODO: calculate metrics and save to /home/user/metrics.json

    plot_feature_importance(model, X.columns)

if __name__ == "__main__":
    df = pd.read_csv('/home/user/sensor_data.csv')
    df_clean = clean_data(df)
    train_and_evaluate(df_clean)
EOF

    chmod -R 777 /home/user
