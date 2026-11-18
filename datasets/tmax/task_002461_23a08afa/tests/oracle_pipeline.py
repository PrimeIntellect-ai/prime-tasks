import sys
import json
import re
import requests
import numpy as np
from sklearn.model_selection import KFold
from sklearn.linear_model import Ridge

def clean_text(text):
    text = text.strip().lower()
    text = re.sub(r'[^a-z0-9 .,]', ' ', text)
    text = re.sub(r' +', ' ', text)
    return text

def main():
    input_data = json.load(sys.stdin)

    cleaned_texts = []
    embeddings = []
    targets = []

    for item in input_data:
        text = item['text']
        target = item['target']
        cleaned = clean_text(text)
        cleaned_texts.append(cleaned)
        targets.append(target)

        resp = requests.get("http://127.0.0.1:8000/embed", params={"text": cleaned})
        embeddings.append(resp.json()['embedding'])

    X = np.array(embeddings)
    y = np.array(targets)

    kf = KFold(n_splits=3, shuffle=False)
    alphas = [0.1, 1.0, 10.0]
    best_alpha = None
    best_mse = float('inf')

    for alpha in alphas:
        model = Ridge(alpha=alpha)
        mses = []
        for train_idx, test_idx in kf.split(X):
            X_train, X_test = X[train_idx], X[test_idx]
            y_train, y_test = y[train_idx], y[test_idx]
            model.fit(X_train, y_train)
            preds = model.predict(X_test)
            mses.append(np.mean((y_test - preds)**2))
        avg_mse = np.mean(mses)

        if avg_mse < best_mse:
            best_mse = avg_mse
            best_alpha = alpha

    result = {
        "optimal_alpha": best_alpha,
        "cleaned_texts": cleaned_texts
    }
    print(json.dumps(result))

if __name__ == "__main__":
    main()
