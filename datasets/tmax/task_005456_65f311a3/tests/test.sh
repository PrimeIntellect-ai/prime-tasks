#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

SCRIPT_FILE = "/home/user/clean_and_benchmark.sh"
VALID_JOINED_FILE = "/home/user/valid_joined.tsv"
BENCHMARK_REPORT_FILE = "/home/user/benchmark_report.tsv"
DATA_DIR = "/home/user/data"

def read_tsv(filepath):
    with open(filepath, 'r') as f:
        return [line.strip("\n").split("\t") for line in f if line.strip("\n")]

def is_positive_int(s):
    try:
        val = float(s)
        if val.is_integer() and val > 0:
            # strictly checking if the string represents an integer, not a float like "15.0"
            # but bash tools might format it differently, so we check if it parses to int
            # actually, age must be a positive integer.
            return int(val) > 0 and s.lstrip("-").isdigit()
    except ValueError:
        pass
    return False

def is_valid_score(s):
    try:
        val = float(s)
        return 0.0 <= val <= 1.0
    except ValueError:
        return False

def test_script_exists():
    assert os.path.isfile(SCRIPT_FILE), f"Script {SCRIPT_FILE} does not exist."

def test_valid_joined_content():
    assert os.path.isfile(VALID_JOINED_FILE), f"Output file {VALID_JOINED_FILE} does not exist."

    users = {row[0]: row[1:] for row in read_tsv(os.path.join(DATA_DIR, "users.tsv"))}
    predictions = {row[0]: row[1:] for row in read_tsv(os.path.join(DATA_DIR, "predictions.tsv"))}
    latencies = {row[0]: row[1:] for row in read_tsv(os.path.join(DATA_DIR, "latency.tsv"))}

    expected_valid_joined = []

    common_users = sorted(list(set(users.keys()) & set(predictions.keys()) & set(latencies.keys())), key=lambda x: int(x))

    for uid in common_users:
        age, country = users[uid]
        model_id, score = predictions[uid]
        latency_ms = latencies[uid][0]

        if is_positive_int(age) and is_valid_score(score) and is_positive_int(latency_ms):
            expected_valid_joined.append([uid, age, country, model_id, score, latency_ms])

    actual_valid_joined = read_tsv(VALID_JOINED_FILE)

    assert len(actual_valid_joined) == len(expected_valid_joined), f"Expected {len(expected_valid_joined)} rows in {VALID_JOINED_FILE}, but got {len(actual_valid_joined)}."

    for actual, expected in zip(actual_valid_joined, expected_valid_joined):
        assert actual == expected, f"Row mismatch in {VALID_JOINED_FILE}. Expected {expected}, got {actual}."

def test_benchmark_report_content():
    assert os.path.isfile(BENCHMARK_REPORT_FILE), f"Output file {BENCHMARK_REPORT_FILE} does not exist."

    # Recompute benchmark report from expected valid joined data
    users = {row[0]: row[1:] for row in read_tsv(os.path.join(DATA_DIR, "users.tsv"))}
    predictions = {row[0]: row[1:] for row in read_tsv(os.path.join(DATA_DIR, "predictions.tsv"))}
    latencies = {row[0]: row[1:] for row in read_tsv(os.path.join(DATA_DIR, "latency.tsv"))}

    common_users = sorted(list(set(users.keys()) & set(predictions.keys()) & set(latencies.keys())), key=lambda x: int(x))

    model_latencies = {}
    for uid in common_users:
        age, country = users[uid]
        model_id, score = predictions[uid]
        latency_ms = latencies[uid][0]

        if is_positive_int(age) and is_valid_score(score) and is_positive_int(latency_ms):
            model_latencies.setdefault(model_id, []).append(int(latency_ms))

    expected_report = []
    for model_id in sorted(model_latencies.keys()):
        avg_latency = sum(model_latencies[model_id]) / len(model_latencies[model_id])
        expected_report.append([model_id, f"{avg_latency:.2f}"])

    actual_report = read_tsv(BENCHMARK_REPORT_FILE)

    assert len(actual_report) == len(expected_report), f"Expected {len(expected_report)} rows in {BENCHMARK_REPORT_FILE}, but got {len(actual_report)}."

    for actual, expected in zip(actual_report, expected_report):
        assert actual == expected, f"Row mismatch in {BENCHMARK_REPORT_FILE}. Expected {expected}, got {actual}."
TEST_EOF

run_script_and_tests() {
    rm -f /home/user/valid_joined.tsv /home/user/benchmark_report.tsv || return 1
    timeout 20s bash /home/user/clean_and_benchmark.sh || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

run_checks() {
    # Execute and validate against the original/current inputs.
    run_script_and_tests || return 1

    # Replace the inputs with an unseen fixture, then require the submitted script
    # to regenerate both outputs. Expected results are recomputed by the tests.
    cat << 'EOF' > /home/user/data/users.tsv
15	33	NZ
11	41	US
12	20.0	UK
13	7	CA
14	8	DE
17	22	BR
18	23	IN
19	24	JP
20	25	AU
21	0	ES
22	26	SE
23	27	NO
24	abc	IT
EOF

    cat << 'EOF' > /home/user/data/predictions.tsv
20	Z5	1.01
18	Z4	nan
15	Z2	0
11	Z2	.5
13	Z1	1
12	Z1	0.4
14	Z3	1.000
17	Z4	1e-1
19	Z5	0.9x
21	Z6	0.2
22	Z7	0.3
24	Z8	0.8
EOF

    cat << 'EOF' > /home/user/data/latency.tsv
17	150
15	200
14	1
13	99
12	88
11	101
18	120
19	130
20	140
21	100
23	160
24	170
EOF

    chmod 666 /home/user/data/users.tsv /home/user/data/predictions.tsv /home/user/data/latency.tsv || return 1
    run_script_and_tests || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
