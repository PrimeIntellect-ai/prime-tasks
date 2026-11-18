#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv gawk
pip3 install pytest pandas scikit-learn numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import numpy as np

# Generate dataset
np.random.seed(42)
ids = np.arange(1, 1001)
sentiments = np.random.choice(['positive', 'negative'], size=1000)
reviews = []
for s in sentiments:
    if s == 'positive':
        words = np.random.choice(['good', 'great', 'excellent', 'amazing', 'happy', 'ok'], size=5)
    else:
        words = np.random.choice(['bad', 'terrible', 'awful', 'sad', 'poor', 'ok'], size=5)
    reviews.append(" ".join(words))

df = pd.DataFrame({'id': ids, 'review_text': reviews, 'sentiment': sentiments})
df.to_csv('/home/user/reviews.csv', index=False)

# Flawed model_pipeline.py
leaky_code = """import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression

df = pd.read_csv('/home/user/reviews.csv')

# LEAKAGE: Vectorizing the entire dataset before splitting
vectorizer = TfidfVectorizer()
X = vectorizer.fit_transform(df['review_text'])
y = df['sentiment']

X_train, X_test, y_train, y_test, id_train, id_test = train_test_split(
    X, y, df['id'], test_size=0.2, random_state=42
)

model = LogisticRegression(random_state=42)
model.fit(X_train, y_train)

predictions = model.predict(X_test)

# Save predictions
out_df = pd.DataFrame({
    'id': id_test,
    'predicted_sentiment': predictions,
    'true_sentiment': y_test
})
out_df.to_csv('/home/user/predictions.csv', index=False)
"""

with open('/home/user/model_pipeline.py', 'w') as f:
    f.write(leaky_code)

os.chmod('/home/user/model_pipeline.py', 0o755)
EOF

python3 /tmp/setup.py

chmod -R 777 /home/user
