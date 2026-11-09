#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os

import numpy as np
import pandas as pd
from scipy import stats
from sklearn.decomposition import TruncatedSVD
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

INPUT = '/home/user/feedback_data.csv'
PROCESSED = '/home/user/processed_feedback.csv'
TOP5 = '/home/user/top_5_support.txt'
RESULTS = '/home/user/stat_results.json'


def trusted_input():
    texts = [
        'The new UI features are fantastic and very fast.',
        'I found a bug in the settings page, it crashes.',
        'Performance is greatly improved in this release.',
        'Customer support was very rude on the phone.',
        'I have been waiting for my ticket to be answered for days.',
        'Can I get a refund for my subscription?',
        'The dashboard layout is confusing and hard to use.',
        'The representative helped me reset my password quickly.',
        'Product works well but lacks advanced export options.',
        'Billing department charged me twice this month.'
    ] * 10
    categories = [
        'Product', 'Product', 'Product', 'Support', 'Support',
        'Support', 'Product', 'Support', 'Product', 'Support'
    ] * 10
    noise_words = ['apple', 'banana', 'orange', 'grape', 'melon']
    texts = [text + ' ' + noise_words[i % 5] for i, text in enumerate(texts)]
    return pd.DataFrame({
        'id': [f'ID_{i:03d}' for i in range(100)],
        'category': categories,
        'text': texts,
    })


def expected_outputs():
    source = trusted_input()
    matrix = TfidfVectorizer(stop_words='english').fit_transform(source['text'])
    embeddings = TruncatedSVD(n_components=5, random_state=42).fit_transform(matrix)
    centroid = embeddings[source['category'].to_numpy() == 'Product'].mean(axis=0)
    similarities = cosine_similarity(embeddings, centroid.reshape(1, -1)).ravel()
    expected = source.copy()
    expected['sim_to_product'] = np.round(similarities, 4)

    # Stable descending ordering preserves source order for equal similarities,
    # matching the original verifier's ordering rule.
    support = expected[expected['category'] == 'Support'].copy()
    support = support.sort_values('sim_to_product', ascending=False, kind='mergesort')
    top_ids = support['id'].head(5).tolist()

    prod = expected.loc[expected['category'] == 'Product', 'sim_to_product'].to_numpy(dtype=float)
    supp = expected.loc[expected['category'] == 'Support', 'sim_to_product'].to_numpy(dtype=float)
    t_result = stats.ttest_ind(prod, supp, equal_var=False)
    mean_diff = float(prod.mean() - supp.mean())
    prod_var = float(prod.var(ddof=1))
    supp_var = float(supp.var(ddof=1))
    se = math.sqrt(prod_var / len(prod) + supp_var / len(supp))
    numerator = (prod_var / len(prod) + supp_var / len(supp)) ** 2
    denominator = ((prod_var / len(prod)) ** 2 / (len(prod) - 1) +
                   (supp_var / len(supp)) ** 2 / (len(supp) - 1))
    dof = numerator / denominator
    margin = float(stats.t.ppf(0.975, dof)) * se
    stat_values = {
        't_statistic': round(float(t_result.statistic), 4),
        'p_value': round(float(t_result.pvalue), 4),
        'ci_lower': round(mean_diff - margin, 4),
        'ci_upper': round(mean_diff + margin, 4),
    }
    return source, expected, top_ids, stat_values


def assert_at_most_four_decimals(raw, label):
    value = raw.strip()
    if 'e' in value.lower():
        # Scientific notation can hide excess precision, so require it to equal
        # its own four-decimal rounding.
        number = float(value)
        assert math.isclose(number, round(number, 4), rel_tol=0, abs_tol=1e-12), \
            f'{label} ({raw}) is not rounded to 4 decimal places.'
    elif '.' in value:
        assert len(value.split('.', 1)[1]) <= 4, \
            f'{label} ({raw}) is not rounded to 4 decimal places.'


def test_source_and_processed_feedback_csv():
    source, expected, _, _ = expected_outputs()
    assert os.path.exists(INPUT), f'File {INPUT} is missing.'
    actual_source = pd.read_csv(INPUT, dtype=str, keep_default_na=False)
    pd.testing.assert_frame_equal(actual_source.reset_index(drop=True), source.astype(str), check_dtype=False)

    assert os.path.exists(PROCESSED), f'File {PROCESSED} is missing.'
    with open(PROCESSED, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        assert fieldnames is not None, f'{PROCESSED} is empty or invalid.'
        assert 'id' in fieldnames, "Column 'id' missing in processed_feedback.csv."
        assert 'category' in fieldnames, "Column 'category' missing in processed_feedback.csv."
        assert 'text' in fieldnames, "Column 'text' missing in processed_feedback.csv."
        assert 'sim_to_product' in fieldnames, "Column 'sim_to_product' missing in processed_feedback.csv."
        assert fieldnames == ['id', 'category', 'text', 'sim_to_product'], \
            f'Unexpected columns or column order: {fieldnames}'
        rows = list(reader)

    assert len(rows) == 100, f'Expected 100 rows in {PROCESSED}, found {len(rows)}.'
    for i, row in enumerate(rows):
        assert row['id'] == expected.at[i, 'id'], f'Incorrect id or row order at row {i}.'
        assert row['category'] == expected.at[i, 'category'], f'Incorrect category for {row["id"]}.'
        assert row['text'] == expected.at[i, 'text'], f'Incorrect text for {row["id"]}.'
        try:
            sim = float(row['sim_to_product'])
        except ValueError:
            raise AssertionError(
                f"sim_to_product value '{row['sim_to_product']}' for id {row['id']} is not a valid float."
            )
        assert math.isfinite(sim), f'sim_to_product for {row["id"]} must be finite.'
        assert_at_most_four_decimals(row['sim_to_product'], f'sim_to_product for {row["id"]}')
        wanted = float(expected.at[i, 'sim_to_product'])
        assert math.isclose(sim, wanted, rel_tol=0, abs_tol=1e-8), \
            f'Incorrect sim_to_product for {row["id"]}: expected {wanted:.4f}, found {sim}.'


def test_top_5_support_txt():
    _, _, expected_ids, _ = expected_outputs()
    assert os.path.exists(TOP5), f'File {TOP5} is missing.'
    with open(TOP5, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 5, f'Expected exactly 5 IDs in {TOP5}, found {len(lines)}.'
    for line in lines:
        assert line.startswith('ID_'), f"Expected ID format 'ID_xxx', found '{line}'."
    assert lines == expected_ids, f'Top 5 IDs do not match the independently computed Support ranking.'

    # Retain the original internal-consistency assertion as well.
    with open(PROCESSED, 'r', encoding='utf-8') as f:
        support_rows = [row for row in csv.DictReader(f) if row.get('category') == 'Support']
    support_rows.sort(key=lambda row: float(row['sim_to_product']), reverse=True)
    internal_ids = [row['id'] for row in support_rows[:5]]
    assert lines == internal_ids, f'Top 5 IDs in {TOP5} do not match the processed CSV.'


def test_stat_results_json():
    _, _, _, expected_stats = expected_outputs()
    assert os.path.exists(RESULTS), f'File {RESULTS} is missing.'
    with open(RESULTS, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f'File {RESULTS} is not valid JSON: {exc}')

    expected_keys = {'t_statistic', 'p_value', 'ci_lower', 'ci_upper'}
    assert set(data.keys()) == expected_keys, \
        f'Expected keys {expected_keys} in {RESULTS}, found {set(data.keys())}.'
    for key in expected_keys:
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), \
            f'Value for {key} must be a number.'
        assert math.isfinite(float(data[key])), f'Value for {key} must be finite.'
        assert_at_most_four_decimals(str(data[key]), f'Value for {key}')
        assert math.isclose(float(data[key]), expected_stats[key], rel_tol=0, abs_tol=1e-8), \
            f'Incorrect {key}: expected {expected_stats[key]}, found {data[key]}.'

    # Retain the original independent t-statistic consistency calculation.
    processed = pd.read_csv(PROCESSED)
    prod = processed.loc[processed['category'] == 'Product', 'sim_to_product'].astype(float).tolist()
    supp = processed.loc[processed['category'] == 'Support', 'sim_to_product'].astype(float).tolist()
    mean_prod = sum(prod) / len(prod)
    mean_supp = sum(supp) / len(supp)
    var_prod = sum((x - mean_prod) ** 2 for x in prod) / (len(prod) - 1)
    var_supp = sum((x - mean_supp) ** 2 for x in supp) / (len(supp) - 1)
    se_diff = math.sqrt(var_prod / len(prod) + var_supp / len(supp))
    t_stat = (mean_prod - mean_supp) / se_diff
    assert math.isclose(abs(float(data['t_statistic'])), abs(t_stat), rel_tol=1e-2), \
        f'Calculated t-statistic {t_stat:.4f} does not match json file {data["t_statistic"]}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
