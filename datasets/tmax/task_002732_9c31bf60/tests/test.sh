#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_report_exists_and_correct():
    report_path = "/home/user/report.txt"
    assert os.path.exists(report_path), f"Expected file {report_path} does not exist."
    assert os.path.isfile(report_path), f"Expected {report_path} to be a file."

    expected_lines = [
        "Category Algebra - Author Frank created expression 100 + 200 which evaluates to 300.",
        "Category Algebra - Author Alice created expression 15 * 3 which evaluates to 45.",
        "Category Geometry - Author Grace created expression 200 - 50 which evaluates to 150.",
        "Category Geometry - Author Dave created expression 12 * 12 which evaluates to 144."
    ]

    with open(report_path, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Report contents are incorrect. Expected:\n{expected_lines}\nGot:\n{actual_lines}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
