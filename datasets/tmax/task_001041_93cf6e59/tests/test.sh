#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import math

def transpose(M):
    return [[M[j][i] for j in range(len(M))] for i in range(len(M[0]))]

def matmul(A, B):
    return [[sum(A[i][k] * B[k][j] for k in range(len(A[0]))) for j in range(len(B[0]))] for i in range(len(A))]

def minor(M, i, j):
    return [row[:j] + row[j+1:] for row in (M[:i] + M[i+1:])]

def det(M):
    if len(M) == 1:
        return M[0][0]
    if len(M) == 2:
        return M[0][0]*M[1][1] - M[0][1]*M[1][0]
    res = 0
    for j in range(len(M)):
        res += ((-1)**j) * M[0][j] * det(minor(M, 0, j))
    return res

def inv(M):
    d = det(M)
    n = len(M)
    res = []
    for i in range(n):
        row = []
        for j in range(n):
            row.append(((-1)**(i+j)) * det(minor(M, i, j)) / d)
        res.append(row)
    return transpose(res)

def clean_data(filepath, has_spend=True):
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        data = []
        for row in reader:
            try:
                # Enforce schema strictly
                id_val = float(row['id'])
                if not id_val.is_integer(): continue
                id_val = int(id_val)

                age_val = float(row['age'])
                if not age_val.is_integer(): continue
                age_val = int(age_val)

                income_val = float(row['income'])
                score_val = float(row['score'])

                if has_spend:
                    spend_val = float(row['spend'])
                else:
                    spend_val = None

                if math.isnan(income_val) or math.isnan(score_val):
                    continue
                if has_spend and math.isnan(spend_val):
                    continue

                d = {'id': id_val, 'age': age_val, 'income': income_val, 'score': score_val}
                if has_spend:
                    d['spend'] = spend_val
                data.append(d)
            except (ValueError, TypeError, KeyError):
                continue
    return data

def mean(xs):
    return sum(xs)/len(xs)

def corr(xs, ys):
    mx = mean(xs)
    my = mean(ys)
    cov = sum((x - mx)*(y - my) for x, y in zip(xs, ys))
    varx = sum((x - mx)**2 for x in xs)
    vary = sum((y - my)**2 for y in ys)
    if varx == 0 or vary == 0:
        return 0
    return cov / math.sqrt(varx * vary)

def test_results_json():
    results_path = '/home/user/results.json'
    assert os.path.isfile(results_path), f"{results_path} does not exist."

    with open(results_path, 'r') as f:
        try:
            student_results = json.load(f)
        except json.JSONDecodeError:
            assert False, "results.json is not valid JSON."

    train_data = clean_data('/home/user/train.csv', has_spend=True)
    test_data = clean_data('/home/user/test.csv', has_spend=False)

    # 2. Correlation
    spends = [d['spend'] for d in train_data]
    corrs = {
        'age': abs(corr([d['age'] for d in train_data], spends)),
        'income': abs(corr([d['income'] for d in train_data], spends)),
        'score': abs(corr([d['score'] for d in train_data], spends))
    }
    top_2 = sorted(corrs.keys(), key=lambda k: corrs[k], reverse=True)[:2]
    top_2.sort()

    # 3. Model
    X = [[1.0, d[top_2[0]], d[top_2[1]]] for d in train_data]
    y = [[d['spend']] for d in train_data]

    Xt = transpose(X)
    XtX = matmul(Xt, X)
    XtX_inv = inv(XtX)
    XtX_inv_Xt = matmul(XtX_inv, Xt)
    beta = matmul(XtX_inv_Xt, y)

    # 4. Predictions
    expected_preds = {}
    for d in test_data:
        pred = beta[0][0] + beta[1][0]*d[top_2[0]] + beta[2][0]*d[top_2[1]]
        expected_preds[str(d['id'])] = round(pred, 2)

    # 5. Similarity
    test_101 = next(d for d in test_data if d['id'] == 101)
    min_dist = float('inf')
    most_sim_id = None
    for d in train_data:
        dist = math.sqrt((d[top_2[0]] - test_101[top_2[0]])**2 + (d[top_2[1]] - test_101[top_2[1]])**2)
        if dist < min_dist:
            min_dist = dist
            most_sim_id = d['id']

    assert "selected_features" in student_results, "Missing 'selected_features' in results.json"
    assert student_results["selected_features"] == top_2, f"Expected selected_features {top_2}, got {student_results['selected_features']}"

    assert "predictions" in student_results, "Missing 'predictions' in results.json"
    student_preds = student_results["predictions"]
    for k, v in expected_preds.items():
        assert k in student_preds, f"Missing prediction for test id {k}"
        assert math.isclose(student_preds[k], v, abs_tol=0.01), f"Expected prediction for {k} to be {v}, got {student_preds[k]}"

    assert "most_similar_train_id_to_test_101" in student_results, "Missing 'most_similar_train_id_to_test_101' in results.json"
    assert student_results["most_similar_train_id_to_test_101"] == most_sim_id, f"Expected most similar id {most_sim_id}, got {student_results['most_similar_train_id_to_test_101']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
