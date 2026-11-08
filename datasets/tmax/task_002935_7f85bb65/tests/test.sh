#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import string
import math
import pytest

def get_clean_data():
    file_path = "/home/user/reviews.csv"
    assert os.path.exists(file_path), f"File {file_path} is missing."

    product_ratings = {}
    product_texts = {}

    with open(file_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rating_str = row.get("rating", "").strip()
            if not rating_str:
                continue

            try:
                pid = int(row["product_id"])
                rating = float(rating_str)
            except ValueError:
                continue

            text = row.get("review_text", "")

            if pid not in product_ratings:
                product_ratings[pid] = []
                product_texts[pid] = []

            product_ratings[pid].append(rating)
            product_texts[pid].append(text)

    # Aggregate
    product_avg_rating = {}
    product_keywords = {}

    for pid in product_ratings:
        avg_rating = sum(product_ratings[pid]) / len(product_ratings[pid])
        product_avg_rating[pid] = avg_rating

        combined_text = " ".join(product_texts[pid])
        # Tokenize: lowercase, remove punctuation (except spaces), split by whitespace
        combined_text = combined_text.lower()
        translator = str.maketrans('', '', string.punctuation)
        clean_text = combined_text.translate(translator)
        keywords = set(clean_text.split())
        product_keywords[pid] = keywords

    return product_avg_rating, product_keywords

def test_recommendations():
    """Test that recommendations.txt contains the correct top 3 similar products."""
    _, product_keywords = get_clean_data()

    assert 101 in product_keywords, "Product 101 not found in cleaned data."
    target_keywords = product_keywords[101]

    similarities = []
    for pid, keywords in product_keywords.items():
        if pid == 101:
            continue
        intersection = len(target_keywords.intersection(keywords))
        union = len(target_keywords.union(keywords))
        jaccard = intersection / union if union > 0 else 0
        similarities.append((jaccard, pid))

    # Sort by similarity descending, then by pid ascending
    similarities.sort(key=lambda x: (-x[0], x[1]))
    top_3 = similarities[:3]
    expected_pids = [str(pid) for _, pid in top_3]
    expected_output = ",".join(expected_pids)

    rec_path = "/home/user/recommendations.txt"
    assert os.path.exists(rec_path), f"File {rec_path} is missing."

    with open(rec_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == expected_output, f"Expected recommendations '{expected_output}', got '{content}'."

def t_pdf(x, df):
    try:
        return math.exp(math.lgamma((df + 1) / 2) - math.lgamma(df / 2)) / math.sqrt(df * math.pi) * (1 + x**2 / df)**(-(df + 1) / 2)
    except ValueError:
        return 0.0

def calculate_p_value(t, df):
    # Simpson's rule for numerical integration to find tail probability
    a = abs(t)
    b = max(a + 100, 100)
    n = 10000
    h = (b - a) / n
    s = t_pdf(a, df) + t_pdf(b, df)
    for i in range(1, n, 2):
        s += 4 * t_pdf(a + i * h, df)
    for i in range(2, n-1, 2):
        s += 2 * t_pdf(a + i * h, df)

    tail_prob = (h / 3) * s
    return 2 * tail_prob

def test_ttest_pvalue():
    """Test that ttest.txt contains the correct rounded p-value."""
    product_avg_rating, product_keywords = get_clean_data()

    group1 = []
    group2 = []

    for pid, keywords in product_keywords.items():
        if "excellent" in keywords:
            group1.append(product_avg_rating[pid])
        else:
            group2.append(product_avg_rating[pid])

    assert len(group1) > 1 and len(group2) > 1, "Not enough data in groups to perform t-test."

    n1 = len(group1)
    n2 = len(group2)
    m1 = sum(group1) / n1
    m2 = sum(group2) / n2

    v1 = sum((x - m1)**2 for x in group1) / (n1 - 1)
    v2 = sum((x - m2)**2 for x in group2) / (n2 - 1)

    t_stat = (m1 - m2) / math.sqrt(v1/n1 + v2/n2)
    df = (v1/n1 + v2/n2)**2 / ( (v1/n1)**2/(n1-1) + (v2/n2)**2/(n2-1) )

    p_val = calculate_p_value(t_stat, df)
    expected_p = f"{p_val:.4f}"

    ttest_path = "/home/user/ttest.txt"
    assert os.path.exists(ttest_path), f"File {ttest_path} is missing."

    with open(ttest_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == expected_p, f"Expected p-value '{expected_p}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
