#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import hashlib
import io
from collections import defaultdict

PROTECTED_CSV = """ReviewID,Timestamp,UserID,ProductID,Rating,ReviewText
1,2023-10-01T10:00:00,U001,PROD_A,5,Great product!
2,2023-10-01T10:05:00,U001,PROD_A,4,Great product!
3,2023-10-02T11:00:00,U002,PROD_A,4,Good value.
4,2023-10-01T09:00:00,U003,PROD_B,2,Did not like it.
5,2023-10-01T08:50:00,U003,PROD_B,2,Did not like it.
6,2023-10-03T14:00:00,U004,PROD_B,1,Terrible.
7,2023-10-04T16:00:00,U005,PROD_B,3,Okay I guess.
8,2023-10-05T08:00:00,U006,PROD_C,5,Perfect!
9,2023-10-05T08:00:01,U006,PROD_C,5,Perfect!
"""

PROTECTED_TEMPLATE = """## Product: {{ProductID}}
- Total Reviews: {{TotalReviews}}
- Average Rating: {{AverageRating}}"""


def test_summary_report_exists_and_correct():
    report_path = '/home/user/summary_report.md'
    csv_path = '/home/user/reviews.csv'
    template_path = '/home/user/template.md'

    assert os.path.isfile(report_path), f"Failure: {report_path} not found."
    assert os.path.isfile(csv_path), f"Failure: {csv_path} not found."
    assert os.path.isfile(template_path), f"Failure: {template_path} not found."

    with open(csv_path, 'r', encoding='utf-8') as f:
        actual_csv = f.read()
    with open(template_path, 'r', encoding='utf-8') as f:
        actual_template = f.read()

    assert actual_csv == PROTECTED_CSV, "Failure: reviews.csv was modified."
    assert actual_template == PROTECTED_TEMPLATE, "Failure: template.md was modified."

    # Read and deduplicate the protected fixture.
    deduped = {}
    reader = csv.DictReader(io.StringIO(PROTECTED_CSV))
    for row in reader:
        hash_str = f"{row['UserID']}|{row['ProductID']}|{row['ReviewText']}"
        h = hashlib.sha256(hash_str.encode('utf-8')).hexdigest()

        if h not in deduped:
            deduped[h] = row
        elif row['Timestamp'] < deduped[h]['Timestamp']:
            deduped[h] = row

    # Compute statistics.
    stats = defaultdict(lambda: {'count': 0, 'sum': 0.0})
    for row in deduped.values():
        pid = row['ProductID']
        stats[pid]['count'] += 1
        stats[pid]['sum'] += float(row['Rating'])

    # Generate the expected report from the protected template. Sections are
    # separated by exactly one blank line.
    sections = []
    for pid in sorted(stats.keys()):
        count = stats[pid]['count']
        avg = stats[pid]['sum'] / count
        section = PROTECTED_TEMPLATE.replace('{{ProductID}}', pid)
        section = section.replace('{{TotalReviews}}', str(count))
        section = section.replace('{{AverageRating}}', f"{avg:.2f}")
        sections.append(section)

    expected_output = (
        "# Product Review Summary\n\n" + "\n\n".join(sections)
    ).strip()

    with open(report_path, 'r', encoding='utf-8') as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, (
        "Failure: Output does not match expected result.\n"
        f"Expected:\n{expected_output}\n\n"
        f"Actual:\n{actual_output}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
